import os
from flask import Flask

app = Flask(__name__)

@app.route("/")
def home():
    return "майнинг работает!"

if __name__ == "__main__":
    from waitress import serve
    port = int(os.environ.get("PORT", 10000))
    serve(app, host="0.0.0.0", port=port)
