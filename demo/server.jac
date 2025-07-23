import sys;
import from mtllm.llm {Model}
import from tools {RagEngine, WebSearch}
import os;
import base64;
import requests;
import anyio;
import mcp_client;

glob rag_engine:RagEngine = RagEngine();
glob llm = Model(model_name='gpt-4o-mini', verbose=True);
glob MCP_SERVER_URL: str = os.getenv('MCP_SERVER_URL', 'http://localhost:8899/mcp');


"""Available tools: 'search_docs' or 'search_web' with {"query": "your query"}.

Only use a dictionary with plain key-value string pairs for `arguments`.
Example input for `use_mcp_tool`:
{
  "name": "search_web",
  "arguments": {"query": "example search"}
}
"""
def use_mcp_tool(name: str, arguments: dict[str, str]) -> str {
    return mcp_client.call_mcp_tool(name=name, arguments=arguments);
}


node Session {
    has id: str;
    has chat_history: list[dict];
    has status: int = 1;

    """Generate a helpful response to the user's message. Use available MCP tools when needed.  
    Must pass arguments as a flat dictionary with string key-value pairs when using the mcp tool.  
    """
    def respond(message:str, chat_history:list[dict]) -> str
        by llm(
            method="ReAct",
            tools=([use_mcp_tool]),
            messages=chat_history,
            max_react_iterations=6
        );
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
    }

    can chat with Session entry {
        here.chat_history.append({"role": "user", "content": self.message});
        response = here.respond(
            message=self.message,
            chat_history=here.chat_history,
        );

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