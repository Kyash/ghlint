function reporter::to_json() {
  jq --seq -sc '
    def merge($rhs):
      .resources.users |= . + $rhs.resources.users |
      .resources.organizations |= . + $rhs.resources.organizations |
      .resources.repositories |= . + $rhs.resources.repositories |
      .results |= . + $rhs.results
    ;
    reduce .[] as $e ({}; merge($e))
  '
}
