@echo off
echo Starting local server at http://localhost:8080
echo Open http://localhost:8080/index.html in your browser.
echo Press Ctrl+C to stop.
npx --yes serve . --listen 8080
