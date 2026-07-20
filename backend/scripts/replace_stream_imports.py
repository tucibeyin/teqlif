import sys

def replace_in_file(filepath):
    with open(filepath, "r") as f:
        content = f.read()

    # Replace specific lines
    content = content.replace("from app.services.stream_service import force_close_stream as _close_stream", "from app.use_cases.streams.commands.force_close_stream import force_close_stream as _close_stream")
    content = content.replace("from app.services.stream_service import force_close_stream", "from app.use_cases.streams.commands.force_close_stream import force_close_stream")
    content = content.replace("from app.services.stream_service import StreamService", "from app.use_cases.streams.legacy_stream import StreamService")

    with open(filepath, "w") as f:
        f.write(content)

if __name__ == "__main__":
    replace_in_file("backend/app/worker.py")
    replace_in_file("backend/app/routers/webhooks.py")
    replace_in_file("backend/app/services/swipe_live_service.py")
    print("Replaced!")
