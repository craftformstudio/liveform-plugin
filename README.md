# Liveform

Liveform teaches your coding agent your standards. Correct it once, it stays corrected.

Private beta: you need an invite to sign in. Request access at [liveform.ai](https://www.liveform.ai).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/stewymccarthy/liveform-plugin/main/install.sh | sh
```

This installs the Liveform program, sets up Claude Code and Cursor when those tools are present, and starts sign-in.

Claude Code users can also add the marketplace, then install the plugin:

```bash
claude plugin marketplace add stewymccarthy/liveform-plugin
claude plugin install liveform@liveform
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/stewymccarthy/liveform-plugin/main/install.sh | sh -s -- --uninstall
```

## Site

https://www.liveform.ai
