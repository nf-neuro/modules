#!/usr/bin/env bash

# Prepare nf-neuro configuration directory and environment file
echo "🔧 Setting up nf-neuro configuration..."
mkdir -p $XDG_CONFIG_HOME/nf-neuro
touch $XDG_CONFIG_HOME/nf-neuro/.env
echo "source $XDG_CONFIG_HOME/nf-neuro/.env" >> ~/.bashrc

# Setup GitHub Actions testing environment
echo "🎭 Setting up GitHub Actions testing tools..."
cat <<'EOF' >> ~/.bashrc

# GitHub Actions Development Aliases
alias act-list='act -l'
alias act-lint='actionlint .github/workflows/*.yml'
alias act-dry='act --dryrun'

alias ga-test='echo "🧪 GitHub Actions Testing Commands:"; echo "  act-list     - List all workflows and jobs"; echo "  act-lint     - Lint workflow files"; echo "  act-dry      - Dry run workflows"'

EOF

echo "✅ GitHub Actions testing environment setup complete!"
echo "Run 'ga-test' to see available testing commands."

# Install nf-test
curl -fsSL https://get.nf-test.com | bash -s "${NFTEST_VERSION}"
sudo mv nf-test /usr/local/bin/.

# Change container bind mounts ownership
echo "🔑 Adjusting permissions for container bind mounts..."
sudo chown -R neuro:neuro $WORKSPACE/.venv
sudo chown -R neuro:neuro $WORKSPACE/tests/.runs
sudo chown -R neuro:neuro /home/neuro/commandhistory
