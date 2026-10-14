# Cedar & Signal

A responsive business website with a chat assistant powered by the local Ollama `qwen3:4b` model. The PowerShell server uses only Windows' built-in runtime and keeps Ollama behind a same-origin API route.

## Run locally

1. Make sure Ollama is running and `ollama list` shows `qwen3:4b`.
2. From this folder, run `powershell -ExecutionPolicy Bypass -File .\server.ps1`.
3. Open [http://localhost:8000](http://localhost:8000).

Set the `OLLAMA_MODEL` or `OLLAMA_URL` environment variables to use a different installed model or Ollama address. The website is served on `127.0.0.1:8000` by default; `-HostAddress` and `-Port` can be passed to the script to change the bind address or port.

The sample business name, services, location, and contact address are written for Cedar & Signal in `index.html`; replace those details with your business information before publishing. The Qwen3 assistant instructions are in `server.ps1`. The server is intended for local development, not direct public deployment.