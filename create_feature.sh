#!/bin/bash
set -euo pipefail

FEATURE_NAME="${1:-}"

if [ -z "$FEATURE_NAME" ]; then
  echo "❌ Please provide a feature name"
  echo "Usage: ./create_feature.sh device_pairing"
  exit 1
fi

APP_NAME="$(grep -E '^name:' pubspec.yaml | head -1 | awk '{print $2}' | tr -d '"')"
if [ -z "$APP_NAME" ]; then
  echo "❌ Could not read app name from pubspec.yaml"
  exit 1
fi

echo "🧱 Creating feature: $FEATURE_NAME (app: $APP_NAME)"
mason make feature --name "$FEATURE_NAME" --app_name "$APP_NAME" -o .
echo "✅ Feature '$FEATURE_NAME' created and wired into DI + routes"
