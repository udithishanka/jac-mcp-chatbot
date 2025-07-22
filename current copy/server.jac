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
            router_node ++> ImageChat();
            router_node ++> VideoChat();
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

    """Generate a helpful response to the user's message. Use available mcp tool when needed.Use list_mcp_tools to find out what are the available tools. Always pass arguments as a flat dictionary (e.g., {\"query\": \"Your search query\"}), never as a list or schema_dict_wrapper. """ 
    def respond(message:str, chat_history:list[dict]) -> str by llm(
            method="ReAct",
            tools=([list_mcp_tools, use_mcp_tool]),
            messages=chat_history,
            max_react_iterations=6
        );
    can chat with infer entry {
        logger.info("interact walker has entered to Imagechat node: %s", visitor.message);
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

# node ImageChat(Chat) {
#     has chat_type: ChatType = ChatType.IMAGE;

#     """Generate a helpful response to the user's message. Use available mcp tool when needed.Use list_mcp_tools to find out what are the available tools. Always pass arguments as a flat dictionary (e.g., {\"query\": \"Your search query\"}), never as a list or schema_dict_wrapper. """ 
#     def respond(message: str) -> str by llm(
#             method="ReAct",
#             tools=([use_mcp_tool, list_mcp_tools]),
#             # messages=chat_history,
#             max_react_iterations=6
#         );

#     """Generate a response to the user's message using an image and text."""
#     def respond_with_image(img: Image, text: Text) -> str by llm(
#         method="Chain-of-Thoughts",
#     );

#     with entry {
#         logger.info("ImageChat node initialized with chat type: IMAGE");
#     }

#     can chat with infer entry {
#         logger.info("interact walker has entered to Imagechat node: %s", visitor.message);
#         img = Image("uploads/user_session_123/photo.jpg");
#         # response = self.respond_with_image(
#         #     img=img,
#         #     text="Describe the image content."
#         # );
#         response = "Image looks great!";
#         visitor.chat_history.append({"role": "assistant", "content": response});
#         self.chat_history = visitor.chat_history;
#         visitor.response = response;
#         print("Response generated:", response);
#         report {"response": response, "chat_history": visitor.chat_history};
#     }
# }



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


walker upload_file {
    has file_name: str;
    has file_data: str;
    has session_id: str;  # To save inside uploads/{session_id}

    can save_doc with `root entry {
        # Ensure uploads/{session_id} directory exists
        upload_dir = os.path.join("uploads", self.session_id);
        if not os.path.exists(upload_dir) {
            os.makedirs(upload_dir);
        }

        file_path = os.path.join(upload_dir, self.file_name);
        data = base64.b64decode(self.file_data.encode('utf-8'));

        with open(file_path, 'wb') as f {
            f.write(data);
        }

        # Only add text-based documents to rag_engine
        lower_name = self.file_name.lower();
        if lower_name.endswith(".pdf") or lower_name.endswith(".txt") {
            rag_engine.add_file(file_path);
        }

        report {
            "status": "uploaded",
            "file_path": file_path,
            "added_to_rag": lower_name.endswith(".pdf") or lower_name.endswith(".txt")
        };
    }
}


