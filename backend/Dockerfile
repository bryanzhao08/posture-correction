FROM python:3.12-slim

# Create a non-root user
RUN useradd -m formcoach
WORKDIR /app

# Install dependencies
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Create data directory and set permissions
RUN mkdir -p /app/data && chown formcoach:formcoach /app/data

# Switch to non-root user
USER formcoach

# Copy the backend code and the shared profiles from the repository root
COPY backend /app/backend
COPY shared /app/shared

# Environment variables
ENV FORMCOACH_DATA_DIR=/app/data
ENV PYTHONPATH=/app

# Default port
EXPOSE 8000

# Start Uvicorn
CMD ["uvicorn", "backend.app.main:app", "--host", "0.0.0.0", "--port", "8000"]
