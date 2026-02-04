#!/bin/bash

# Usage: ./build-image.sh <phpVersion> <imageType> [--push] [--platform=<platform>] [--chromium]
# Example: ./build-image.sh 8.4 fpm
# Example: ./build-image.sh 8.3 openswoole --push
# Example: ./build-image.sh 8.4 openswoole --platform=linux/arm64
# Example: ./build-image.sh 8.4 fpm --push --platform=linux/amd64
# Example: ./build-image.sh 8.4 fpm --chromium

imageVersion=1.3

set -e

# Validate required arguments
if [ $# -lt 2 ]; then
  echo "❌ Error: Missing required arguments"
  echo "Usage: $0 <phpVersion> <imageType> [--push] [--platform=<platform>] [--chromium]"
  echo "Example: $0 8.4 fpm"
  echo "Example: $0 8.4 fpm --push --platform=linux/arm64"
  echo "Example: $0 8.4 fpm --chromium"
  exit 1
fi

phpVersion="$1"
imageType="$2"
shift 2

# Parse optional flags
push=""
platform=""
chromium=""
chromiumSuffix=""
chromiumBuildArg=""

for arg in "$@"; do
  case "$arg" in
    --push)
      push="--push"
      ;;
    --platform=*)
      platform="${arg#*=}"
      ;;
    --chromium)
      chromium="true"
      chromiumSuffix="-chromium"
      chromiumBuildArg="--build-arg INSTALL_CHROMIUM=true"
      ;;
    *)
      echo "⚠️  Unknown argument: $arg"
      exit 1
      ;;
  esac
done

imageTag="ghcr.io/forlaravel/docker:${imageVersion}-php${phpVersion}-${imageType}${chromiumSuffix}"
latestTag="ghcr.io/forlaravel/docker:latest-php${phpVersion}-${imageType}${chromiumSuffix}"
dockerfilePath="./src/php-${imageType}/Dockerfile"

echo "⚪️ Building image: ${imageTag}"
echo "⚪️ Also tagging:   ${latestTag}"
echo "Using Dockerfile: ${dockerfilePath}"
[ "$chromium" == "true" ] && echo "🌐 Chromium: enabled (INSTALL_CHROMIUM=true)"

# Detect current architecture if platform not specified
if [ -z "$platform" ]; then
  arch=$(uname -m)
  case "$arch" in
    x86_64)
      platform="linux/amd64"
      ;;
    aarch64|arm64)
      platform="linux/arm64"
      ;;
    *)
      echo "⚠️  Unknown architecture: $arch, defaulting to linux/amd64"
      platform="linux/amd64"
      ;;
  esac
  echo "🔍 Auto-detected platform: ${platform}"
else
  echo "🎯 Using specified platform: ${platform}"
fi

# Decide whether to push or load (default: build only, no push)
if [ "$push" == "--push" ]; then
  outputFlag="--push"
  echo "📤 Push enabled: Image will be pushed to the registry"
else
  outputFlag="--load"
  echo "📦 Local build mode: Image will be loaded locally (no push)"
fi
echo "🏗️  Building for platform: ${platform}"

docker buildx build \
  --platform "${platform}" \
  --build-arg INPUT_PHP="${phpVersion}" \
  ${chromiumBuildArg} \
  --tag "${imageTag}" \
  --tag "${latestTag}" \
  --file "${dockerfilePath}" \
  ${outputFlag} .

echo
echo "✅ Image built successfully: ${imageTag}"
echo "✅ Also tagged: ${latestTag}"
[ "$push" == "--push" ] && echo "🌍 Image pushed to registry"
echo
