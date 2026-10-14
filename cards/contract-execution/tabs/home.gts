import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { LegalHome } from '../../legal/components/legal-home';
interface Signature {
  Args: { app: ContractExecutionView };
}

export class HomeTab extends GlimmerComponent<Signature> {
  <template>
    <LegalHome
      @app.context={{@app.context}}
      @realms={{@app.realmList}}
      @onOpen={{@app.openInWorkspace}}
    />

    <style scoped></style>
  </template>
}
