from flask import Flask
import psycopg2
import os

app = Flask(__name__)

DB_HOST = os.environ.get("DB_HOST")
DB_USER = os.environ.get("DB_USER")
DB_PASS = os.environ.get("DB_PASS")
DB_NAME = os.environ.get("DB_NAME")

@app.route("/")
def get_secret_from_rds():
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS
        )
        cursor = conn.cursor()
        
        cursor.execute("SELECT secret_value FROM my_secrets LIMIT 1;")
        secret = cursor.fetchone()[0]
        
        return f"<h1>Success!</h1><p>The secret retrieved from AWS RDS is: <strong>{secret}</strong></p>"
        
    except Exception as e:
        return f"<h1>Error connecting to RDS</h1><p>{str(e)}</p>"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)