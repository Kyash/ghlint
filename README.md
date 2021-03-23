# githublint

[![Docker](https://github.com/Kyash/githublint/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/Kyash/githublint/actions/workflows/docker-publish.yml)

Find problems in your GitHub settings.

## Installation

```sh
git clone git@github.com:Kyash/githublint.git
cd githublint
install -m 755 ./bin/githublint /usr/local/bin
```

## Prerequisites

- Docker

## Usage

Displayed by executing the following command:

```sh
githublint -h
```

### Example

```
githublint orgs/Kyash > results.tsv
```

## Exit status

- `0`: There was no rule violation
- `1`: One or more rule violations found
- other: An unexpected error has occurred

## Configure rules

Describe the rule settings in `.githublintrc.json`.

- For example, describe `rules::repo::manage_team_access` settings in `.rules.repo.manage_team_access.patterns` element
- Multiple settings can be described in `patterns` element
- Use `filter` element to specify targets
  - To exclude all targets from the rule, describe the pattern element as follows: `{ "filter": { "name": "^$" } }`
- Other rule-specific settings can also be described.

### Example

If `Kyash` organization expects all repositories to have write permission from `engineer` team, then describe:

```json
{
  "rules": {
    "repo": {
      "manage_team_access": {
        "patterns": [
          {
            "filter": {
              "full_name": "^Kyash/"
            },
            "allowlist": [
              {
                "slug": "engineer",
                "permission": "push",
                "strict": true
              }
            ]
          }
        ]
      }
    }
  }
}
```

## Development

### Getting Started

Launch the development environment

```sh
bash -i ./launch_dev_env.sh
```

### Testing

Use [Bats-core](https://github.com/bats-core/bats-core) to run the test.

```sh
bats -r test
```

### Dependencies

- GitHub REST API
- cURL v7.75.0+
- Bash v5.0+
- Node.js v10.24.0+
- jq v1.6+

### Further reading

- [Generating a new SSH key and adding it to the ssh-agent - GitHub Docs](https://docs.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Kyash/githublint
