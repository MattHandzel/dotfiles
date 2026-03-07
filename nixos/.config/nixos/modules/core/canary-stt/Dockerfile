FROM nvcr.io/nvidia/pytorch:25.02-py3

# Install system dependencies
RUN apt-get update && apt-get install -y libsndfile1 ffmpeg git python3-setuptools && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# API and NeMo Requirements
# We install setuptools<70 because newer versions removed pkg_resources which NeMo depends on
RUN pip install --no-cache-dir \
    fastapi \
    uvicorn \
    python-multipart \
    pydantic \
    omegaconf \
    "setuptools<70" \
    torchcodec \
    "transformers>=4.45.0"

# Install NeMo
RUN pip install --no-cache-dir git+https://github.com/NVIDIA/NeMo.git#egg=nemo_toolkit[asr]

# Re-install torchaudio and torchvision (sometimes NeMo downgrades them)
RUN pip install --no-cache-dir torchaudio torchvision

# Expose the API port
EXPOSE 8001

# Copy the server script
COPY main.py /app/main.py

# Run the FastAPI server
CMD ["python", "main.py"]
