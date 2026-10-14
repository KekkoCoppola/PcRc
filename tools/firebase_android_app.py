"""Registra l'app Android nel progetto Firebase (solo la prima volta) e scrive
app/android/app/google-services.json, necessario alle notifiche push (FCM).

Usa la chiave dell'account di servizio dell'agent:
    python tools/firebase_android_app.py
"""
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, project_management

PACKAGE = "com.example.pcrc"  # applicationId in app/android/app/build.gradle.kts
ROOT = Path(__file__).resolve().parents[1]
KEY = ROOT / "agent" / "firebase_key.json"
OUT = ROOT / "app" / "android" / "app" / "google-services.json"


def main():
    firebase_admin.initialize_app(credentials.Certificate(KEY))
    app = next((a for a in project_management.list_android_apps()
                if a.get_metadata().package_name == PACKAGE), None)
    if app is None:
        app = project_management.create_android_app(PACKAGE, display_name="PcRc")
        print(f"App Android {PACKAGE} registrata su Firebase")
    OUT.write_text(app.get_config(), encoding="utf-8")
    print(f"Scritto {OUT}")


if __name__ == "__main__":
    main()
