#!/bin/bash
# Switch between standard and RotorQuant llama-server images.
#
# Usage:
#   ./switch-version.sh prism        # Use PrismML fork (ternary Bonsai + all GGUF)
#   ./switch-version.sh standard     # Use upstream llama.cpp
#   ./switch-version.sh rotorquant   # Use RotorQuant fork
#   ./switch-version.sh status       # Show current version
#   ./switch-version.sh build        # (Re)build the rotorquant image
#   ./switch-version.sh build-prism  # Download + (re)build the prism image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ROTORQUANT_BUILD="/home/genar/src/rotorquant-test/llama-cpp-turboquant/build/bin"

# PrismML llama.cpp fork release. Pinned deliberately: the newest tag may ship
# Windows assets only for a while after publication. cuda-12.8 is the build that
# carries sm_120 (Blackwell / RTX 5080).
PRISM_RELEASE="prism-b10685-7dffb15"
PRISM_ASSET="llama-prism-b10685-7dffb15-bin-linux-cuda-12.8-x64.tar.gz"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

current_tag() {
    grep "^IMAGE_TAG=" .env 2>/dev/null | cut -d= -f2 || echo "standard"
}

set_tag() {
    local tag="$1"
    if grep -q "^IMAGE_TAG=" .env 2>/dev/null; then
        sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=$tag/" .env
    else
        echo "IMAGE_TAG=$tag" >> .env
    fi

    # Keep DOCKERFILE in step with IMAGE_TAG. docker-compose.yml carries a
    # build: section, so without this `docker compose up -d` would rebuild a
    # missing llama-server:<tag> from the stock Dockerfile and silently serve
    # the wrong binary under the right tag.
    local dockerfile
    case "$tag" in
        prism)      dockerfile="Dockerfile.prism" ;;
        rotorquant) dockerfile="Dockerfile.rotorquant" ;;
        *)          dockerfile="Dockerfile" ;;
    esac
    if grep -q "^DOCKERFILE=" .env 2>/dev/null; then
        sed -i "s/^DOCKERFILE=.*/DOCKERFILE=$dockerfile/" .env
    else
        echo "DOCKERFILE=$dockerfile" >> .env
    fi
}

show_status() {
    local tag
    tag=$(current_tag)
    echo ""
    echo -e "Current version: ${GREEN}${tag}${NC}"
    if docker ps --format '{{.Names}}' | grep -q "^llama-server$"; then
        echo -e "Container: ${GREEN}running${NC}"
        docker ps --filter "name=llama-server" --format "  Image: {{.Image}}  Status: {{.Status}}"
    else
        echo -e "Container: ${RED}stopped${NC}"
    fi
    echo ""
}

build_rotorquant() {
    echo -e "${BLUE}Staging RotorQuant binaries from $ROTORQUANT_BUILD...${NC}"
    if [ ! -f "$ROTORQUANT_BUILD/llama-server" ]; then
        echo -e "${RED}ERROR: binary not found at $ROTORQUANT_BUILD/llama-server${NC}"
        echo "Build it first in ~/src/rotorquant-test/llama-cpp-turboquant"
        exit 1
    fi

    rm -rf rotorquant-bin
    mkdir -p rotorquant-bin
    cp "$ROTORQUANT_BUILD/llama-server" rotorquant-bin/
    cp "$ROTORQUANT_BUILD/llama-cli" rotorquant-bin/ 2>/dev/null || true
    cp "$ROTORQUANT_BUILD"/*.so* rotorquant-bin/ 2>/dev/null || true
    echo -e "${GREEN}✅ Binaries staged ($(ls rotorquant-bin | wc -l) files)${NC}"

    echo -e "${BLUE}Building llama-server:rotorquant image...${NC}"
    docker build -f Dockerfile.rotorquant -t llama-server:rotorquant .
    echo -e "${GREEN}✅ Image built: llama-server:rotorquant${NC}"
}

build_prism() {
    if [ ! -f "prism-bin/llama-server" ]; then
        echo -e "${BLUE}Downloading PrismML fork ${PRISM_RELEASE}...${NC}"
        local url="https://github.com/PrismML-Eng/llama.cpp/releases/download/${PRISM_RELEASE}/${PRISM_ASSET}"
        rm -rf prism-bin && mkdir -p prism-bin
        curl -fL --progress-bar -o /tmp/${PRISM_ASSET} "$url" || {
            echo -e "${RED}ERROR: download failed: $url${NC}"; exit 1; }
        tar xzf /tmp/${PRISM_ASSET} -C prism-bin --strip-components=1
        rm -f /tmp/${PRISM_ASSET}
        chmod +x prism-bin/llama-* 2>/dev/null || true
    fi
    echo -e "${GREEN}Binaries staged ($(ls prism-bin | wc -l) files)${NC}"

    echo -e "${BLUE}Building llama-server:prism image...${NC}"
    docker build -f Dockerfile.prism -t llama-server:prism .
    echo -e "${GREEN}Image built: llama-server:prism${NC}"
}

case "${1:-status}" in
    prism)
        echo -e "${YELLOW}Switching to prism...${NC}"
        if ! docker image inspect llama-server:prism &>/dev/null; then
            echo "Image llama-server:prism not found - building first..."
            build_prism
        fi
        set_tag "prism"
        docker compose up -d
        show_status
        ;;

    build-prism)
        build_prism
        ;;

    standard)
        echo -e "${YELLOW}Switching to standard...${NC}"
        set_tag "standard"
        docker compose up -d
        show_status
        ;;

    rotorquant|rotor)
        echo -e "${YELLOW}Switching to rotorquant...${NC}"
        if ! docker image inspect llama-server:rotorquant &>/dev/null; then
            echo "Image llama-server:rotorquant not found — building first..."
            build_rotorquant
        fi
        set_tag "rotorquant"
        docker compose up -d
        show_status
        ;;

    build)
        build_rotorquant
        ;;

    status)
        show_status
        ;;

    *)
        echo "Usage: $0 {prism|standard|rotorquant|build|build-prism|status}"
        echo ""
        echo "  prism       - Run PrismML fork image (ternary Bonsai + all conventional GGUF)"
        echo "  build-prism - Download the pinned fork release and (re)build llama-server:prism"
        echo "  standard    - Run upstream llama.cpp image (llama-server:standard)"
        echo "  rotorquant  - Run RotorQuant image (builds if not yet built)"
        echo "  build       - (Re)build the rotorquant image from local binary"
        echo "  status      - Show current version and container state"
        exit 1
        ;;
esac
