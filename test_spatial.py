import anthropic
import base64

client = anthropic.Anthropic(api_key="YOURKEY")

with open(r"C:\Projects\Tilism\First\latest_frame.jpg", "rb") as f:
    img = base64.b64encode(f.read()).decode()

question = """Look at this image. The image contains 2 circles, one red and one white. It also contains a white arrow pointing upwards. You are looking at a birds eye view. Tell me in one word whether the white circle is to the left or to the right of the red circle."""

for i in range(20):
    r = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=50,
        messages=[{
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": img
                    }
                },
                {
                    "type": "text",
                    "text": question
                }
            ]
        }]
    )
    print(f"Run {i+1}: {r.content[0].text.strip()}")