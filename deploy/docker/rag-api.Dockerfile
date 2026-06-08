FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY deploy/docker/rag-api-requirements.txt /tmp/rag-api-requirements.txt
RUN pip install --no-cache-dir -r /tmp/rag-api-requirements.txt

COPY services/rag-api/app /app/app

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
