import psycopg2
import os
import secrets
import string

alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
random_password = ''.join(secrets.choice(alphabet) for i in range(16))

conn = psycopg2.connect(
    host=os.environ.get('DB_HOST'),
    database=os.environ.get('DB_NAME'),
    user=os.environ.get('DB_USER'),
    password=os.environ.get('DB_PASS'),
    sslmode='require'
)
cursor = conn.cursor()

cursor.execute("""
CREATE TABLE IF NOT EXISTS my_secrets (
    id SERIAL PRIMARY KEY,
    secret_value VARCHAR(255) NOT NULL
);
""")

cursor.execute("TRUNCATE TABLE my_secrets RESTART IDENTITY;")

cursor.execute("INSERT INTO my_secrets (secret_value) VALUES (%s);", (random_password,))

conn.commit()
cursor.close()
conn.close()

print("Database seeded successfully with a new secure random password!")