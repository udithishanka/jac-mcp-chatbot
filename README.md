# jac-rag-chatbot

This project demonstrates a simple Retrieval-Augmented Generation (RAG) chatbot built with Jaseci. It exposes a Streamlit based front‑end and an API powered back‑end.

The server now integrates optional web search via the [Serper](https://serper.dev) API. Set the `SERPER_API_KEY` environment variable before starting the server to enable this feature.

## MCP Integration

This repo also exposes a simple [Model Context Protocol](https://github.com/anthropic-ai/mcp) server. Start it with `jac run mcp_server.jac` to provide additional tools over MCP. When enabled, the backend will connect to the MCP server specified by the `MCP_SERVER_URL` environment variable (defaults to `http://localhost:8899/mcp`) and let the language model call the registered tools during a chat session.

## How to Run

### Install Dependencies

Install the necessary dependencies:

```bash
pip install jaclang jac-cloud jac-streamlit mtllm langchain langchain-community langchain-openai langchain-chroma chromadb openai pypdf tiktoken requests mcp[cli] anyio
```

### Environment Setup

To use the Web Search, get a free API key from [Serper](https://serper.dev):

```bash
export OPENAI_API_KEY=<your-openai-key>
export SERPER_API_KEY=<your-serper-key>
```

### Running the Application

You'll need three terminals to run the complete application:

**Terminal 1 - MCP Server:**
```bash
jac run mcp_server.jac
```

**Terminal 2 - Main Server:**
```bash
jac serve server.jac
```

**Terminal 3 - Frontend:**
```bash
jac streamlit client.jac
```

## Uploading PDFs

1. Start the Jaseci server with `server.jac`.
2. Launch the Streamlit app using `client.jac`.
3. Use the *Upload PDF* widget to select PDF files. The files are sent to the back‑end and stored under the `docs/` directory. The RAG engine indexes them immediately so future questions can reference their content.
