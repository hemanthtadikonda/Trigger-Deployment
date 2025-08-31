from flask import Flask, request, render_template_string
import subprocess

app = Flask(__name__)

HTML_FORM = """
<!doctype html>
<title>Trigger Deployment</title>
<h2>Enter Deployment Details</h2>
<form method="post">
  <input type="text" name="image" placeholder="nginx:latest" required><br><br>
  <input type="text" name="cluster" placeholder="https://API-SERVER-ENDPOINT" required><br><br>
  <input type="text" name="token" placeholder="Cluster Token" required><br><br>
  <input type="submit" value="Deploy">
</form>
<p>{{ message }}</p>
"""

@app.route("/", methods=["GET", "POST"])
def deploy():
    message = ""
    if request.method == "POST":
        image_name = request.form["image"]
        cluster_name = request.form["cluster"]
        token = request.form["token"]

        try:
            result = subprocess.run(
                ["./deploy.sh", image_name, cluster_name, token],
                capture_output=True, text=True, check=True
            )
            message = f"✅ Deployment triggered<br><pre>{result.stdout}</pre>"
        except subprocess.CalledProcessError as e:
            message = f"❌ Error:<br><pre>{e.stderr}</pre>"

    return render_template_string(HTML_FORM, message=message)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
