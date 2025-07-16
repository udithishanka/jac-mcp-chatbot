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


# Routing enum and nodes
enum ChatType {
    RAG = "RAG",
    QA = "QA"
}

node Router {
    "Classify the message as RAG (needs document retrieval) or QA (can answer directly)"
    def classify(message: str) -> ChatType by llm(method="Reason", temperature=0.0);
}

node Chat {
    has chat_type: ChatType;
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
    "Respond to message using only chat history (QA)"
    def respond(message: str, chat_history: list[dict]) -> str {
        return llm(
            method="ReAct",
            tools=([use_mcp_tool]),
            messages=chat_history,
            max_react_iterations=6
        );
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
}


walker interact {
    has message: str;
    has session_id: str;

    can init_session with `root entry {
        visit [-->](`?Session)(?id == self.session_id) else {
            session_node = here ++> Session(id=self.session_id, chat_history=[], status=1);
            print("Session Node Created");
            visit session_node;
        }
        # Ensure router and chat nodes exist
        visit [-->](`?Router) else {
            router_node = here ++> Router();
            router_node ++> RagChat();
            router_node ++> QAChat();
            visit router_node;
        }
    }

    can chat with Session entry {
        here.chat_history.append({"role": "user", "content": self.message});
        # Route the message
        router = here.root().out("Router")[0];
        chat_type = router.classify(self.message);
        if chat_type == ChatType.RAG {
            rag_node = router.out("RagChat")[0];
            response = rag_node.respond(self.message, here.chat_history);
        } else {
            qa_node = router.out("QAChat")[0];
            response = qa_node.respond(self.message, here.chat_history);
        }
        here.chat_history.append({"role": "assistant", "content": response});
        report {"response": response};
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
        visit [-->](`?Router) else {
            router_node = here ++> Router();
            router_node ++> RagChat();
            router_node ++> QAChat();
            visit router_node;
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
        context_msg = f"User uploaded an image '{self.file_name}'. Analysis: {desc}";
        here.chat_history.append({"role": "system", "content": context_msg});
        if self.message {
            here.chat_history.append({"role": "user", "content": self.message});
            # Route the message
            router = here.root().out("Router")[0];
            chat_type = router.classify(self.message);
            if chat_type == ChatType.RAG {
                rag_node = router.out("RagChat")[0];
                response = rag_node.respond(self.message, here.chat_history);
            } else {
                qa_node = router.out("QAChat")[0];
                response = qa_node.respond(self.message, here.chat_history);
            }
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
        visit [-->](`?Router) else {
            router_node = here ++> Router();
            router_node ++> RagChat();
            router_node ++> QAChat();
            visit router_node;
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
        context_msg = f"User uploaded a video '{self.file_name}'. Summary: {summary}";
        here.chat_history.append({"role": "system", "content": context_msg});
        if self.message {
            here.chat_history.append({"role": "user", "content": self.message});
            # Route the message
            router = here.root().out("Router")[0];
            chat_type = router.classify(self.message);
            if chat_type == ChatType.RAG {
                rag_node = router.out("RagChat")[0];
                response = rag_node.respond(self.message, here.chat_history);
            } else {
                qa_node = router.out("QAChat")[0];
                response = qa_node.respond(self.message, here.chat_history);
            }
            here.chat_history.append({"role": "assistant", "content": response});
            report {"summary": summary, "response": response};
        } else {
            report {"summary": summary};
        }
    }
}