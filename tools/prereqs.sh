#riscv-opcodes
#TBD - insert pre-reqs

#Spike
sudo apt-get install -y \
    device-tree-compiler \
    libboost-regex-dev \
    libboost-system-dev \
    gcc \
    g++ \
    make \
    autoconf \
    automake \
    autotools-dev \
    curl \
    python3 \
    libmpc-dev \
    libmpfr-dev \
    libgmp-dev \
    gawk \
    jq \
    build-essential \
    bison \
    flex \
    texinfo \
    gperf \
    libtool \
    patchutils \
    bc \
    zlib1g-dev \
    libexpat-dev \
    lcov \
    libssl-dev \
    libgtk-3-dev \
    zenity

CARGO_MIN_VERSION="1.70.0"

if command -v cargo &> /dev/null; then
    INSTALLED=$(cargo --version | awk '{print $2}')
    echo "Cargo already installed: $INSTALLED"

    # Compare versions
    if printf '%s\n' "$CARGO_MIN_VERSION" "$INSTALLED" | sort -V -C; then
        echo "Version is sufficient, skipping install."
    else
        echo "Warning: installed version $INSTALLED is older "
        echo "   than required $CARGO_MIN_VERSION"
        echo "Consider running: rustup update"
    fi
else
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    source ~/.cargo/env
fi
