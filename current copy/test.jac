import from mtllm.llm {Model}
import from mtllm.types {Image, Video, Text}

glob llm = Model(model_name='gpt-4o-mini', verbose=True);


"""Generate a response to the user's message using the provided image and text."""
def respond_with_image(img: Image, text: Text) -> str by llm();

with entry {
    message = "Describe the image content.";
    response = respond_with_image(
            img=Image("/home/udith/jaseci_mtllm_pg/jac-rag-chatbot/current copy/uploads/user_session_123/photo.jpg"),
            text=message
        );
}