Companion

INSTALL
Drag Companion.app to Applications, then launch it from Applications.
Grant Accessibility and Input Monitoring if macOS asks.
On a new Mac, enter your own provider API key in setup. Keys are device-local
and are never included in this disk image.

USE
Select text in an editor and press Command-Shift-E.
Press Return to fix grammar, or Tab to enter a custom instruction.
To skip the icons, choose Settings > General > Open with > Instruction field.
Include "use web search" in your typed instruction to search online.
Search costs extra and sends context to the search provider. Avoid private
details. Sources are in History, not in the pasted text.
The rewrite replaces the selection and stays on the clipboard.
Use your editor's normal Command-Z to undo a paste.

SETTINGS
Open Settings from Companion's menu bar icon.
Writing contains the two model choices and the grammar prompt.
Providers contains Keychain-backed API keys and optional local models.
New installs use Gemini 3.5 Flash Lite for instructions and DeepSeek V4.1 Flash
for grammar through OpenRouter. Upgrades preserve saved model choices.
You need your own provider account/key; API usage is billed by the provider.

UPGRADING
1. Quit the old Companion from its menu bar icon before replacing it.
2. Drag this Companion.app into Applications and choose Replace.
3. Launch /Applications/Companion.app, not a copy inside this disk image.
4. Eject the disk image. About Companion should show version 0.4.0.

Do not keep an older copy running or launch multiple copies from Downloads,
mounted disk images, or other folders. This disk image does not automatically
quit or replace a running app.

Saved provider/model choices, prompts, history, and Keychain keys are retained.
To use the recommended pair, choose Settings > Providers > Use recommended models.
If an old setup points to an unconfigured provider, reselect your provider
and model in Settings. Installing an update does not supply missing API keys.
If the shortcut or text replacement does not work, check System Settings >
Privacy & Security > Accessibility and Input Monitoring. If necessary, remove
the stale Companion entry, add the app from Applications, and relaunch it.

Your grammar configuration is preserved. Retired action presets are exported
to a recovery file before removal. Writing can reveal the recovery file.
If a selection cannot be verified or output is incomplete, Companion keeps
the generated text available for recovery without replacing the original.

Native Liquid Glass requires macOS 26 or later. Earlier supported macOS
versions use native material. Companion supports macOS 13+ on Intel and
Apple Silicon.

Made by santiagoalonso.com
