from flask import Flask, render_template, request, redirect, url_for
from flask_sqlalchemy import SQLAlchemy
import boto3
import os

app = Flask(__name__)

# --- CONFIGURATION ---
# We use os.environ.get() so these are not hardcoded in the AMI.
# We will pass these values in later via Terraform User Data.
RDS_ENDPOINT = os.environ.get('RDS_ENDPOINT')
S3_BUCKET    = os.environ.get('S3_BUCKET_NAME')
DB_USER      = os.environ.get('DB_USER')
DB_PASSWORD  = os.environ.get('DB_PASSWORD')
DB_NAME      = "flask_db"

# Construct the Database URL
app.config['SQLALCHEMY_DATABASE_URI'] = f"postgresql://{DB_USER}:{DB_PASSWORD}@{RDS_ENDPOINT}/{DB_NAME}"
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)
s3 = boto3.client('s3', region_name='us-east-1')

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    image_url = db.Column(db.String(200), nullable=True) # Stores filename only

@app.route('/')
def index():
    users = User.query.all()
    # Generate Pre-signed URLs for S3 images so they can be viewed securely
    for user in users:
        if user.image_url:
            try:
                user.image_url = s3.generate_presigned_url('get_object',
                    Params={'Bucket': S3_BUCKET, 'Key': user.image_url},
                    ExpiresIn=3600)
            except Exception as e:
                print(f"Error generating URL: {e}")
    return render_template('index.html', users=users)

@app.route('/add', methods=['POST'])
def add_user():
    username = request.form['username']
    image = request.files['image']
    
    s3_key = None
    if image:
        s3_key = image.filename
        # Upload directly to S3
        try:
            s3.upload_fileobj(image, S3_BUCKET, s3_key)
        except Exception as e:
            print(f"Error uploading to S3: {e}")
            return "Error uploading image", 500

    new_user = User(username=username, image_url=s3_key)
    db.session.add(new_user)
    db.session.commit()
    return redirect(url_for('index'))

# --- CRITICAL FIX: TABLE CREATION ---
# This ensures Gunicorn creates tables on startup
with app.app_context():
    db.create_all()
# ------------------------------------

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)