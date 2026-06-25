.PHONY: sync-css

# Copy canonical CSS and brand-mark SVG from html/ into the VSCode webview directory.
# Run this after any change to html/styles.css or html/icon.svg.
sync-css:
	cp html/styles.css vscode-extension/webview/styles.css
	@echo "styles.css synced -> vscode-extension/webview/styles.css"
	cp html/icon.svg vscode-extension/webview/icon.svg
	@echo "icon.svg synced -> vscode-extension/webview/icon.svg"
