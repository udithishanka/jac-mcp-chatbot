with entry {

    """Generate a helpful response to the user's message. Use available mcp tool when needed.Use list_mcp_tools to find out what are the available tools. Always pass arguments as a flat dictionary (e.g., {\"query\": \"Your search query\"}), never as a list or schema_dict_wrapper. """ 
    def respond(message:str) -> str by llm(
            method="ReAct",
            tools=([list_mcp_tools, use_mcp_tool]),
            # messages=chat_history,
            max_react_iterations=6
        );

    message = "What is the weather like today?";
    response = respond(
            message=message,
            # chat_history=visitor.chat_history,
    );
    logger.info("Response generated at Image: %s", response);
    
    print("ImageChatNode created:", ImageChatNode);
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