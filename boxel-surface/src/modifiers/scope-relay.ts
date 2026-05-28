import { modifier } from 'ember-modifier';

import {
  createSurfaceScopeRelay,
  surfaceScopeAttributesForTree,
  type SurfaceScopeRelay,
} from '../scope-relay.ts';

export interface SurfaceScopeRelayOptions {
  relay?: SurfaceScopeRelay;
}

const surfaceScopeRelay = modifier<{
  Element: HTMLElement;
  Args: {
    Positional: [SurfaceScopeRelay?];
    Named: SurfaceScopeRelayOptions;
  };
}>((element, positional, options = {}) => {
  const relay = options.relay ?? positional[0] ?? createSurfaceScopeRelay();
  relay.adopt(surfaceScopeAttributesForTree(element));
  relay.stamp(element);

  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node instanceof Element) {
          relay.stamp(node);
        }
      }
    }
  });

  observer.observe(element, {
    childList: true,
    subtree: true,
  });

  return () => observer.disconnect();
});

export default surfaceScopeRelay;
