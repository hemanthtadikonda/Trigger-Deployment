#!/usr/bin/env python3
"""
Simple K8s Portal (lightweight)

Flow:
 - User provides cluster API + token once at top (consent).
 - Use forms for Deployment, Service, or Custom YAML.
 - If kubectl missing -> run install_kubectl.sh synchronously.
 - Create temporary kubeconfig (token auth), run kubectl apply/delete, show results.
"""

from flask import Flask, render_template, request
import os
import shutil
import subprocess
import tempfile
import yaml
import base64
import sys

app = Flask(__name__, template_folder="templates", static_folder="static")

INSTALL_SCRIPT = os.path.join(os.path.dirname(__file__), "install_kubectl.sh")


# ---------- helpers ----------

def kubectl_path():
    """Return path to kubectl binary. If not found, try installing via script."""
    path = shutil.which("kubectl")
    if path:
        return path

    # kubectl not found -> attempt install
    if os.path.exists(INSTALL_SCRIPT) and os.access(INSTALL_SCRIPT, os.X_OK):
        try:
            # run script synchronously and let it print its output
            subprocess.run([INSTALL_SCRIPT], check=True)
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Failed to install kubectl: {e}")
        # re-check
        path = shutil.which("kubectl")
        if path:
            return path
        # maybe installed to /tmp/kubectl
        if os.path.exists("/tmp/kubectl") and os.access("/tmp/kubectl", os.X_OK):
            return "/tmp/kubectl"
    raise RuntimeError("kubectl not found. Please install kubectl or make install_kubectl.sh executable.")


def build_kubeconfig(api_server: str, token: str, namespace: str = "default", skip_tls: bool = False, ca_pem: str = None) -> str:
    """Create a temporary kubeconfig file and return its path."""
    kubeconfig = {
        "apiVersion": "v1",
        "kind": "Config",
        "clusters": [
            {
                "name": "portal-cluster",
                "cluster": { "server": api_server }
            }
        ],
        "users": [
            {
                "name": "portal-user",
                "user": { "token": token }
            }
        ],
        "contexts": [
            {
                "name": "portal-context",
                "context": { "cluster": "portal-cluster", "user": "portal-user", "namespace": namespace }
            }
        ],
        "current-context": "portal-context"
    }

    if skip_tls:
        kubeconfig["clusters"][0]["cluster"]["insecure-skip-tls-verify"] = True
    elif ca_pem:
        kubeconfig["clusters"][0]["cluster"]["certificate-authority-data"] = base64.b64encode(ca_pem.encode()).decode()

    fd, path = tempfile.mkstemp(prefix="kubeconf_", suffix=".yaml")
    with os.fdopen(fd, "w") as f:
        yaml.safe_dump(kubeconfig, f, default_flow_style=False)
    return path


def run_kubectl_apply(yaml_text: str, kubeconfig_path: str, namespace: str = "default"):
    """Run kubectl apply -n <namespace> -f - and return (ok, stdout, stderr)."""
    env = os.environ.copy()
    env["KUBECONFIG"] = kubeconfig_path

    # connectivity quick-check
    conn = subprocess.run(["kubectl", "get", "ns"], capture_output=True, text=True, env=env)
    if conn.returncode != 0:
        return False, conn.stdout or "", conn.stderr or "Connectivity check failed"

    proc = subprocess.run(["kubectl", "apply", "-n", namespace, "-f", "-"], input=yaml_text, text=True, capture_output=True, env=env)
    return (proc.returncode == 0), proc.stdout or "", proc.stderr or ""


def run_kubectl_delete(kind: str, name: str, kubeconfig_path: str, namespace: str = "default"):
    env = os.environ.copy()
    env["KUBECONFIG"] = kubeconfig_path
    proc = subprocess.run(["kubectl", "delete", kind, name, "-n", namespace], capture_output=True, text=True, env=env)
    return (proc.returncode == 0), proc.stdout or "", proc.stderr or ""


# ---------- routes ----------

@app.route("/")
def index():
    """
    Main page: includes a credentials section (API + token) that is used across forms.
    The forms submit cluster api/token along with their resource-specific fields.
    """
    return render_template("index.html")


@app.route("/deploy", methods=["POST"])
def deploy():
    api = request.form.get("api", "").strip()
    token = request.form.get("token", "").strip()
    namespace = request.form.get("namespace", "default").strip() or "default"
    skip_tls = True if request.form.get("skip_tls") else False
    ca_cert = request.form.get("ca_cert", "").strip() or None

    name = request.form.get("name", "").strip()
    image = request.form.get("image", "").strip()
    replicas = request.form.get("replicas", "1").strip()

    if not (api and token and name and image):
        return "api, token, name and image are required", 400

    yaml_text = f"""apiVersion: apps/v1
kind: Deployment
metadata:
  name: {name}
  labels:
    app: {name}
spec:
  replicas: {replicas}
  selector:
    matchLabels:
      app: {name}
  template:
    metadata:
      labels:
        app: {name}
    spec:
      containers:
      - name: {name}
        image: {image}
"""

    try:
        kubectl_path()  # will install if missing (or raise)
    except Exception as e:
        return render_template("result.html", yaml=yaml_text, ok=False, stdout="", stderr=str(e), kind="Deployment", name=name)

    kc_path = None
    try:
        kc_path = build_kubeconfig(api, token, namespace, skip_tls=skip_tls, ca_pem=ca_cert)
        ok, out, err = run_kubectl_apply(yaml_text, kc_path, namespace)
        return render_template("result.html", yaml=yaml_text, ok=ok, stdout=out, stderr=err, kind="Deployment", name=name)
    finally:
        if kc_path and os.path.exists(kc_path):
            os.remove(kc_path)


@app.route("/service", methods=["POST"])
def service():
    api = request.form.get("api", "").strip()
    token = request.form.get("token", "").strip()
    namespace = request.form.get("namespace", "default").strip() or "default"
    skip_tls = True if request.form.get("skip_tls") else False
    ca_cert = request.form.get("ca_cert", "").strip() or None

    name = request.form.get("name", "").strip()
    port = request.form.get("port", "80").strip()
    target = request.form.get("targetPort", port).strip()

    if not (api and token and name):
        return "api, token and name are required", 400

    yaml_text = f"""apiVersion: v1
kind: Service
metadata:
  name: {name}
spec:
  selector:
    app: {name}
  ports:
    - protocol: TCP
      port: {port}
      targetPort: {target}
  type: ClusterIP
"""

    try:
        kubectl_path()
    except Exception as e:
        return render_template("result.html", yaml=yaml_text, ok=False, stdout="", stderr=str(e), kind="Service", name=name)

    kc_path = None
    try:
        kc_path = build_kubeconfig(api, token, namespace, skip_tls=skip_tls, ca_pem=ca_cert)
        ok, out, err = run_kubectl_apply(yaml_text, kc_path, namespace)
        return render_template("result.html", yaml=yaml_text, ok=ok, stdout=out, stderr=err, kind="Service", name=name)
    finally:
        if kc_path and os.path.exists(kc_path):
            os.remove(kc_path)


@app.route("/custom", methods=["POST"])
def custom():
    api = request.form.get("api", "").strip()
    token = request.form.get("token", "").strip()
    namespace = request.form.get("namespace", "default").strip() or "default"
    skip_tls = True if request.form.get("skip_tls") else False
    ca_cert = request.form.get("ca_cert", "").strip() or None

    yaml_text = request.form.get("yaml", "").strip()
    if not (api and token and yaml_text):
        return "api, token and yaml are required", 400

    try:
        kubectl_path()
    except Exception as e:
        return render_template("result.html", yaml=yaml_text, ok=False, stdout="", stderr=str(e), kind="Custom", name="(custom)")

    kc_path = None
    try:
        kc_path = build_kubeconfig(api, token, namespace, skip_tls=skip_tls, ca_pem=ca_cert)
        ok, out, err = run_kubectl_apply(yaml_text, kc_path, namespace)
        return render_template("result.html", yaml=yaml_text, ok=ok, stdout=out, stderr=err, kind="Custom", name="(custom)")
    finally:
        if kc_path and os.path.exists(kc_path):
            os.remove(kc_path)


@app.route("/delete", methods=["POST"])
def delete():
    api = request.form.get("api", "").strip()
    token = request.form.get("token", "").strip()
    namespace = request.form.get("namespace", "default").strip() or "default"
    skip_tls = True if request.form.get("skip_tls") else False
    ca_cert = request.form.get("ca_cert", "").strip() or None

    kind = request.form.get("kind", "").strip()
    name = request.form.get("name", "").strip()

    if not (api and token and kind and name):
        return "api, token, kind and name are required", 400

    try:
        kubectl_path()
    except Exception as e:
        return render_template("result.html", yaml="", ok=False, stdout="", stderr=str(e), kind=kind, name=name)

    kc_path = None
    try:
        kc_path = build_kubeconfig(api, token, namespace, skip_tls=skip_tls, ca_pem=ca_cert)
        ok, out, err = run_kubectl_delete(kind, name, kc_path, namespace)
        return render_template("result.html", yaml=f"# delete {kind}/{name}", ok=ok, stdout=out, stderr=err, kind=kind, name=name)
    finally:
        if kc_path and os.path.exists(kc_path):
            os.remove(kc_path)


if __name__ == "__main__":
    if sys.version_info < (3,8):
        print("Recommended: python 3.8+")
    app.run(host="0.0.0.0", port=5000, debug=True)
