import sys;
import logging;
import from mtllm.llm {Model}
import from mtllm.types {Image, Video, Text}
import from tools {RagEngine}
import os;
import base64;
import requests;
import anyio;
import mcp_client;

with entry {
    logger = logging.getLogger(__name__);
    logger.setLevel(logging.INFO);
    logging.basicConfig(level=logging.INFO);
}

glob rag_engine:RagEngine = RagEngine();
glob llm = Model(model_name='gpt-4o-mini', verbose=True);
glob MCP_SERVER_URL: str = os.getenv('MCP_SERVER_URL', 'http://localhost:8899/mcp');


"""ChatType enum defines the types of chat interactions. ChatType must be one of:
- RAG: For interactions that require document retrieval.
- QA: For interactions that can be answered directly without document retrieval.
- IMAGE: For interactions involving image analysis.
- VIDEO: For interactions involving video analysis.
"""
enum ChatType {
    RAG = "RAG",
    QA = "QA",
    IMAGE = "IMAGE",
    VIDEO = "VIDEO"
}


node Router {
    "Classify the message as RAG, QA, IMAGE, or VIDEO. If classification fails, default to QA."
    def classify(message: str) -> ChatType by llm(method="Reason", temperature=0.8);
}

node Chat {
    has chat_type: ChatType;
}

"""Get available MCP tool names."""
def list_mcp_tools() -> list[str] {
    logger.info("Listing available MCP tools...");
    return mcp_client.list_mcp_tools();
}

"""Use MCP tool to perform actions. 
name must be one of available tools from list_mcp_tools(), do not make up any tool names.

Example input for `use_mcp_tool`:
{"name": "tool_name", "arguments": {"query": "your query"}}
"""
def use_mcp_tool(name: str, arguments: dict[str, str]) -> str {
    logger.info(f"Calling MCP tool: {name} with arguments: {arguments}");
    return mcp_client.call_mcp_tool(name=name, arguments=arguments);
}

walker infer {
    has message:str;
    has chat_history: list[dict];

    can init_router with `root entry {
        visit [-->](`?Router) else {
            router_node = here ++> Router();
            router_node ++> RagChat();
            router_node ++> QAChat();
            visit router_node;
        }
    }
    can route with Router entry {
        classification = here.classify(message = self.message);
        print("Routing message:", self.message, "to chat type:", classification);
        visit [-->](`?Chat)(?chat_type==classification);
    }
}


node ImageChat(Chat) {
    has chat_type: ChatType = ChatType.IMAGE;
    "Respond to message using image analysis (IMAGE)"
    def respond(message: str, chat_history: list[dict]) -> str by llm(
            method="ReAct",
            tools=([use_mcp_tool, list_mcp_tools]),
            messages=chat_history,
            context=context,
            max_react_iterations=6
        );
    }
    can chat with infer entry {
        # Sync walker chat_history with node chat_histor
        print("interact walker has entered to Imagechat node", visitor.message);
        response = self.respond(
            message=visitor.message,
            chat_history=visitor.chat_history,
        );
        visitor.chat_history.append({"role": "assistant", "content": response});
        self.chat_history = visitor.chat_history;
        visitor.response = response;
        report {"response": response, "chat_history": visitor.chat_history};
}


node VideoChat(Chat) {
    has chat_type: ChatType = ChatType.VIDEO;
    "Respond to message using video analysis (VIDEO)"
    def respond(message: str, chat_history: list[dict]) -> str by llm(
            method="ReAct",
            tools=([list_mcp_tools, use_mcp_tool]),
            max_react_iterations=6
        );
    }
    can chat with infer entry {
        # Sync walker chat_history with node chat_histor
        print("interact walker has entered to Videochat node", visitor.message);
        response = self.respond(
            message=visitor.message,
            chat_history=visitor.chat_history,
        );
        visitor.chat_history.append({"role": "assistant", "content": response});
        self.chat_history = visitor.chat_history;
        visitor.response = response;
        report {"response": response, "chat_history": visitor.chat_history};
}

node RagChat(Chat) {
    has chat_type: ChatType = ChatType.RAG;

    """Generate a helpful response to the user's message. Use available mcp tool when needed.Use list_mcp_tools to find out what are the available tools. Always pass arguments as a flat dictionary (e.g., {\"query\": \"Your search query\"}), never as a list or schema_dict_wrapper. """ 
    def respond(message:str, chat_history:list[dict]) -> str by llm(
            method="ReAct",
            tools=([list_mcp_tools, use_mcp_tool]),
            messages=chat_history,
            max_react_iterations=6
        );
    can chat with infer entry {
        logger.info("interact walker has entered to Ragchat node: %s", visitor.message);
        response = self.respond(
            message=visitor.message,
            chat_history=visitor.chat_history,
        );
        logger.info("Response generated at RAG: %s", response);
        visitor.chat_history.append({"role": "assistant", "content": response});
        self.chat_history = visitor.chat_history;
        visitor.response = response;
        report {"response": response, "chat_history": visitor.chat_history};
    }
}

node QAChat(Chat) {
    has chat_type: ChatType = ChatType.QA;

    """Generate a helpful response to the user's message. Use available mcp tool when needed. Always pass arguments as a flat dictionary (e.g., {\"query\": \"Your search query\"}), never as a list or schema_dict_wrapper. """ 
    def respond(message:str, chat_history:list[dict]) -> str
        by llm(
            method="ReAct",
            tools=([use_mcp_tool, list_mcp_tools]),
            messages=chat_history,
            max_react_iterations=6
        );

    can chat with infer entry {
        print("interact walker has entered chat with message:", visitor.message);
        response = self.respond(
            message=visitor.message,
            chat_history=visitor.chat_history,
        );
        visitor.chat_history.append({"role": "assistant", "content": response});
        self.chat_history = visitor.chat_history;
        visitor.response = response;
        print("Response generated:", response);
        report {"response": response, "chat_history": visitor.chat_history};
    } 
}

walker interact {
    has message: str;
    has session_id: str;
    has chat_history: list[dict] = [];

    can init_session with `root entry {
        visit [-->](`?Session)(?id == self.session_id) else {
            session_node = here ++> Session(id=self.session_id, chat_history=[], status=1);
            print("Session Node Created");
            visit session_node;
        }
    }
}



node Session {
    has id: str;
    has chat_history: list[dict];
    has status: int = 1;

    """Generate a helpful response to the user's message. Use available mcp tool when needed. Always pass arguments as a flat dictionary (e.g., {\"query\": \"Your search query\"}), never as a list or schema_dict_wrapper. """
    def respond(message:str, chat_history:list[dict]) -> str
        by llm(
            method="ReAct",
            tools=([use_mcp_tool]),
            messages=chat_history,
            max_react_iterations=6
        );

    def chat_with_image(img: Image, text: Text) -> str by llm();

    def chat_with_video(video: Video, text: Text) -> str by llm(method="Chain-of-Thoughts");

    can chat with interact entry {
        # Sync walker chat_history with node chat_history
        visitor.chat_history = self.chat_history;
        visitor.chat_history.append({"role": "user", "content": visitor.message});
        response = infer(message=visitor.message, chat_history=self.chat_history) spawn root;
        print("Response from infer:", response.response);
        visitor.chat_history.append({"role": "assistant", "content": response.response});
        self.chat_history = visitor.chat_history;
        report {"response": response.response};
    }
}


walker upload_pdf {
    has file_name: str;
    has file_data: str;

    can save_doc with `root entry {
        if not os.path.exists(rag_engine.file_path) {
            os.makedirs(rag_engine.file_path);
        }
        file_path = os.path.join(rag_engine.file_path, self.file_name);
        data = base64.b64decode(self.file_data.encode('utf-8'));
        with open(file_path, 'wb') as f {
            f.write(data);
        }
        rag_engine.add_file(file_path);
        report {"status": "uploaded"};
    }
}


walker analyze_image {
    has file_name: str;
    has file_data: str;
    has session_id: str;
    has message: str = None;

    can init_session with `root entry {
         visit [-->](`?Session)(?id == self.session_id) else {
            session_node = here ++> Session(id=self.session_id, chat_history=[], status=1);
            print("Session Node Created for image analysis");
            visit session_node;
        }
    }

    can chat with Session entry {
        if not os.path.exists('uploads') {
            os.makedirs('uploads');
        }
        file_path = os.path.join('uploads', self.file_name);
        data = base64.b64decode(self.file_data.encode('utf-8'));
        with open(file_path, 'wb') as f {
            f.write(data);
        }
        img = Image(file_path);
        text = self.message if self.message else "Describe the image content.";
        desc = here.chat_with_image(img, text);

        # Add to chat history as a system message about the uploaded image
        context_msg = f"User uploaded an image '{self.file_name}'. Analysis: {desc}";
        here.chat_history.append({"role": "system", "content": context_msg});

        if self.message {
            here.chat_history.append({"role": "user", "content": self.message});
            response = here.chat_with_image(
                img=img,
                text=self.message,
                chat_history=here.chat_history
            );
            here.chat_history.append({"role": "assistant", "content": response});
            report {"description": desc, "response": response};
        } else {
            report {"description": desc};
        }
    }
}

walker analyze_video {
    has file_name: str;
    has file_data: str;
    has session_id: str;
    has message: str = None;

    can init_session with `root entry {
         visit [-->](`?Session)(?id == self.session_id) else {
            session_node = here ++> Session(id=self.session_id, chat_history=[], status=1);
            print("Session Node Created for video analysis");
            visit session_node;
        }
    }

    can summarize with Session entry {
        if not os.path.exists('uploads') {
            os.makedirs('uploads');
        }
        file_path = os.path.join('uploads', self.file_name);
        data = base64.b64decode(self.file_data.encode('utf-8'));
        with open(file_path, 'wb') as f {
            f.write(data);
        }
        video = Video(file_path, 1);
        text = self.message if self.message else "Summarize the video content.";
        summary = here.chat_with_video(video, text);

        # Add to chat history as a system message about the uploaded video
        context_msg = f"User uploaded a video '{self.file_name}'. Summary: {summary}";
        here.chat_history.append({"role": "system", "content": context_msg});

        if self.message {
            here.chat_history.append({"role": "user", "content": self.message});
            response = here.chat_with_video(
                video=video,
                text=self.message,
                chat_history=here.chat_history
            );
            here.chat_history.append({"role": "assistant", "content": response});
            report {"summary": summary, "response": response};
        } else {
            report {"summary": summary};
        }
    }
}