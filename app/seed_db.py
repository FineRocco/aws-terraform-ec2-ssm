import psycopg2
import os

conn = psycopg2.connect(
    host=os.environ.get('DB_HOST'),
    database=os.environ.get('DB_NAME'),
    user=os.environ.get('DB_USER'),
    password=os.environ.get('DB_PASS')
)
cursor = conn.cursor()

# Create the table
cursor.execute("""
CREATE TABLE IF NOT EXISTS my_secrets (
    id SERIAL PRIMARY KEY,
    secret_value VARCHAR(255) NOT NULL
);
""")

# Insert the winning secret
cursor.execute("INSERT INTO my_secrets (secret_value) VALUES ('Zero-Knowledge DevSecOps Achieved!');")

conn.commit()
cursor.close()
conn.close()
print("Database seeded successfully!")