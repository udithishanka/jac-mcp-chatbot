import sys;
import from mtllm.llm {Model}
import from mtllm.types {Image, Video, Text}
import from tools {RagEngine}
import os;
import base64;
import requests;
import anyio;
import mcp_client;

glob rag_engine:RagEngine = RagEngine();
glob llm = Model(model_name='gpt-4o-mini');
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
    # def classify(message: str) -> ChatType by llm(method="Reason", temperature=0.8);
    def classify(message: str) -> str {
        return ChatType.QA;
    }
}

node Chat {
    has chat_type: ChatType;
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
        # classification = here.classify(message = self.message);
        classification = ChatType.QA;  # Default to QA for simplicity
        print("Routing message:", self.message, "to chat type:", classification);
        visit [-->](`?Chat)(?chat_type==classification);
    }
}

node RagChat(Chat) {
    has chat_type: ChatType = ChatType.RAG;
    "Respond to message using document retrieval (RAG)"
    def respond(message: str, chat_history: list[dict]) -> str {
        # Retrieve context from RAG engine
        context = rag_engine.get_from_chroma(query=message);
        return llm(
            method="ReAct",
            tools=([use_mcp_tool]),
            messages=chat_history,
            context=context,
            max_react_iterations=6
        );
    }
    
}

node QAChat(Chat) {
    has chat_type: ChatType = ChatType.QA;

    "Generate a helpful response to the user's message. Use available mcp tool when needed. Consider any uploaded media context."
    def respond(message:str, chat_history:list[dict]) -> str
        by llm(
            method="ReAct",
            tools=([use_mcp_tool]),
            messages=chat_history,
            max_react_iterations=6
        );

    can chat with infer entry {
        # Sync walker chat_history with node chat_history
        # visitor.chat_history = self.chat_history;
        print("interact walker has entered chat with message:", visitor.message);
        # visitor.chat_history.append({"role": "user", "content": visitor.message});
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


"""Available tools: 'search_docs' or 'search_web' with {"query": "your query"}.

Only use a dictionary with plain key-value string pairs for `arguments`.
Example:
{
  "name": "search_web",
  "arguments": {"query": "example search"}
}
"""
def use_mcp_tool(name: str, arguments: dict[str, str]) -> str {
    return mcp_client.call_mcp_tool(name=name, arguments=arguments);;
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

    "Generate a helpful response to the user's message. Use available mcp tool when needed. Consider any uploaded media context."
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