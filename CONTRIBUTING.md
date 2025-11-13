# Contributing to Forkspoon

Thank you for your interest in contributing to Forkspoon! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please be respectful and constructive in all interactions.

## How to Contribute

### Reporting Issues

1. Check if the issue already exists
2. Include:
   - Clear description of the problem
   - Steps to reproduce
   - Expected vs actual behavior
   - System information (OS, Go version, kernel version)
   - Relevant logs

### Suggesting Features

1. Open a discussion first
2. Explain the use case
3. Provide examples
4. Consider implementation complexity

### Submitting Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests if applicable
5. Run tests (`make test-all`)
6. Format code (`make fmt`)
7. Commit with clear messages
8. Push to your fork
9. Open a Pull Request

## Development Setup

```bash
# Clone your fork
git clone https://github.com/yourusername/forkspoon.git
cd forkspoon

# Install development tools
make dev-setup

# Create a branch
git checkout -b feature/my-feature

# Make changes and test
make test-all

# Format and check
make pre-commit
```

## Coding Standards

### Go Code Style

- Follow standard Go conventions
- Use `gofmt` and `goimports`
- Add comments for exported functions
- Keep functions small and focused
- Handle errors explicitly

### Commit Messages

Format:
```
type: brief description

Longer explanation if needed.

Fixes #123
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `test`: Testing
- `perf`: Performance
- `refactor`: Code restructuring
- `style`: Formatting
- `chore`: Maintenance

### Testing

- Write unit tests for new functions
- Add integration tests for new features
- Ensure all tests pass
- Aim for good coverage

### Documentation

- Update README if needed
- Add inline documentation
- Include examples
- Update IMPLEMENTATION_GUIDE if applicable

## Testing Checklist

Before submitting:

- [ ] Code compiles (`make build`)
- [ ] Tests pass (`make test-all`)
- [ ] Code formatted (`make fmt`)
- [ ] No lint errors (`make lint`)
- [ ] Documentation updated
- [ ] Commit messages clear
- [ ] PR description complete

## Review Process

1. Automated checks run
2. Code review by maintainer
3. Feedback addressed
4. Approved and merged

## Release Process

1. Version tagged following semver
2. Changelog updated
3. Binaries built for all platforms
4. Release notes published

## Getting Help

- Open an issue for bugs
- Use discussions for questions
- Check existing documentation
- Ask in PR comments

## Recognition

Contributors are recognized in:
- README.md
- Release notes
- Contributors file

Thank you for contributing!