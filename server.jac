import sys;
import logging;
import from mtllm.llm {Model}
import from rag {RagEngine, WebSearch}
import os;
import base64;
import requests;
import anyio;
import mcp_client;

glob rag_engine:RagEngine = RagEngine();
glob llm = Model(model_name='gpt-4o', verbose=True, temperature=0.8);
glob MCP_SERVER_URL: str = os.getenv('MCP_SERVER_URL', 'http://localhost:8899/mcp');

with entry {
    logger = logging.getLogger(__name__);
    logger.setLevel(logging.INFO);
    logging.basicConfig(level=logging.INFO);
}


# """Available tools: 'search_docs' or 'search_web' with {"query": "your query"}.

# Example:
# {"name": "search_docs", "arguments": {"query": "example"}}
# """
"""Use MCP tool to perform actions. name must be one of available tools, do not make up any tool names.
MUST provide a str input to `use_mcp_tool`'s `arguments` field, NOT a list.
arguments'key is always 'query' and value is the search query.
Example input for `use_mcp_tool`:
{"name": "tool_name", "arguments": {"query": "your query"}}

!!IMPORTANT - Avoid using a list for `arguments` as it will not work with the MCP tool call.
"""
def use_mcp_tool(name: str, arguments: dict[str, str]) -> str {
    return mcp_client.call_mcp_tool(name=name, arguments=arguments);
}


"""List available MCP tools."""
def list_mcp_tools() -> list[str] {
    logger.info("Listing available MCP tools...");
    return mcp_client.list_mcp_tools();
}


node Session {
    has id: str;
    has chat_history: list[dict];
    has status: int = 1;

    """Generate a helpful response to the user's message. Use available mcp tool when needed. Always pass arguments as a flat dictionary (e.g., {\"query\": \"Trincomalee, Sri Lanka\"}), never as a list or schema_dict_wrapper."""
    def respond(message:str, chat_history:list[dict]) -> str
        by llm(
            method="ReAct",
            tools=([list_mcp_tools, use_mcp_tool]),
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




