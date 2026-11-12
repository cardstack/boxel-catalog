import { CardDef, contains, field } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import {
  instance,
  operation,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import GitBranchIcon from '@cardstack/boxel-icons/git-branch';

// A GitHub repository, with the one outside call the open-issues digest
// automation makes: the repository's open issues, read with the caller's own
// GitHub key.
export class GitHubRepository extends CardDef {
  static displayName = 'GitHub Repository';
  static icon = GitBranchIcon;

  @field owner = contains(StringField);
  @field repo = contains(StringField);

  @operation static openIssues = {
    base: 'callApi',
    label: 'List a repository’s open issues, with your GitHub key',
    url: 'https://api.github.com/repos/{owner}/{repo}/issues',
    path: { owner: instance('owner'), repo: instance('repo') },
    query: { state: 'open', per_page: '100' },
    headers: {
      accept: 'application/vnd.github+json',
      authorization: 'Bearer {{userKey}}',
    },
  } satisfies OperationDeclaration;
}
