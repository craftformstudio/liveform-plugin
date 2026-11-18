# Liveform

Liveform teaches your coding agent your standards. Correct it once, it stays corrected.

Private beta: you need an invite to sign in. Request access at [liveform.ai](https://liveform.ai).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/craftformstudio/liveform-plugin/main/install.sh | sh
```

This installs the Liveform program, sets up Claude Code and Cursor when those tools are present, and starts sign-in.

Claude Code users can also add the marketplace, then install the plugin:

```bash
claude plugin marketplace add craftformstudio/liveform-plugin
claude plugin install liveform@liveform
```

## Check it's on

Liveform is on in every project you open in Claude Code or Cursor. Type `/liveform` in either to see where it stands. `/liveform off` turns it off for one project, `/liveform on` turns it back on, and `/liveform signin` signs you in again.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/craftformstudio/liveform-plugin/main/install.sh | sh -s -- --uninstall
```

## Site

https://liveform.ai
