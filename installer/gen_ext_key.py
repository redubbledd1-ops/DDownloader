import base64, hashlib, json, subprocess, sys
from pathlib import Path

try:
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.hazmat.primitives import serialization
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "cryptography", "-q"])
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.hazmat.primitives import serialization

root = Path(r"C:\Users\redub\Desktop\Projects\Downloader")
installer = root / "installer"
installer.mkdir(exist_ok=True)
pem_path = installer / "extension-key.pem"
id_path = installer / "extension-id.txt"
manifest_path = root / "extension" / "manifest.json"

if pem_path.exists():
    private_key = serialization.load_pem_private_key(pem_path.read_bytes(), password=None)
else:
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    pem_path.write_bytes(pem)

public_der = private_key.public_key().public_bytes(
    encoding=serialization.Encoding.DER,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
)
manifest_key = base64.b64encode(public_der).decode("ascii")
digest = hashlib.sha256(public_der).digest()[:16]
ext_id = "".join(
    chr(ord("a") + ((b >> 4) & 0xF)) + chr(ord("a") + (b & 0xF)) for b in digest
)

id_path.write_text(f"ExtensionId={ext_id}\nManifestKey={manifest_key}\n", encoding="ascii")

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["key"] = manifest_key
manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("EXT_ID=" + ext_id)
print("manifest key updated")
