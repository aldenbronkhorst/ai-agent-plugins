import assert from "node:assert/strict";
import { runGraphRequest } from "../scripts/graph_request.mjs";

function createDependencies({
  cached = false,
  authenticatedAccount = "first@example.com",
  silentError = null,
} = {}) {
  const state = {
    deleted: 0,
    deviceCodeCalls: 0,
    silentCalls: 0,
    fetchCalls: 0,
    persistenceConfiguration: null,
  };
  const persistence = {
    async delete() {
      state.deleted += 1;
      return true;
    },
  };

  class FakePublicClientApplication {
    async getAllAccounts() {
      return cached ? [{ username: "first@example.com" }] : [];
    }

    async acquireTokenSilent() {
      state.silentCalls += 1;
      if (silentError) {
        throw silentError;
      }
      return {
        accessToken: "silent-token",
        account: { username: authenticatedAccount },
      };
    }

    async acquireTokenByDeviceCode(request) {
      state.deviceCodeCalls += 1;
      request.deviceCodeCallback({ message: "TEST DEVICE CODE" });
      return {
        accessToken: "device-token",
        account: { username: authenticatedAccount },
      };
    }
  }

  const dependencies = {
    msalNode: { PublicClientApplication: FakePublicClientApplication },
    msalExtensions: {
      DataProtectionScope: { CurrentUser: "CurrentUser" },
      PersistenceCreator: {
        async createPersistence(configuration) {
          state.persistenceConfiguration = configuration;
          return persistence;
        },
      },
      PersistenceCachePlugin: class PersistenceCachePlugin {},
    },
    async fetchImpl(url, request) {
      state.fetchCalls += 1;
      assert.equal(url.href, "https://graph.microsoft.com/v1.0/me");
      assert.match(request.headers.Authorization, /^Bearer (device|silent)-token$/);
      return new Response(JSON.stringify({ id: "user-one" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    },
  };
  return { dependencies, state };
}

const baseOptions = {
  account: "first@example.com",
  method: "GET",
  uri: "/v1.0/me",
  scopesJson: '["User.Read"]',
  environment: "Global",
  stateDir: "/tmp/microsoft-graph-test-state",
};

{
  const { dependencies, state } = createDependencies();
  const result = await runGraphRequest(baseOptions, dependencies);
  assert.deepEqual(JSON.parse(result), { id: "user-one" });
  assert.equal(state.deviceCodeCalls, 1);
  assert.equal(state.silentCalls, 0);
  assert.equal(state.fetchCalls, 1);
  assert.equal(state.persistenceConfiguration.usePlaintextFileOnLinux, false);
  assert.equal(state.persistenceConfiguration.dataProtectionScope, "CurrentUser");
}

{
  const { dependencies, state } = createDependencies({
    cached: true,
    silentError: { errorCode: "invalid_grant" },
  });
  await runGraphRequest(baseOptions, dependencies);
  assert.equal(state.silentCalls, 1);
  assert.equal(state.deviceCodeCalls, 1);
  assert.equal(state.fetchCalls, 1);
}

{
  const { dependencies, state } = createDependencies({ cached: true });
  await runGraphRequest(baseOptions, dependencies);
  assert.equal(state.silentCalls, 1);
  assert.equal(state.deviceCodeCalls, 0);
}

{
  const { dependencies, state } = createDependencies({ authenticatedAccount: "wrong@example.com" });
  await assert.rejects(
    runGraphRequest(baseOptions, dependencies),
    /instead of 'first@example.com'/,
  );
  assert.equal(state.deleted, 1);
  assert.equal(state.fetchCalls, 0);
}

{
  const { dependencies, state } = createDependencies();
  await assert.rejects(
    runGraphRequest({ ...baseOptions, uri: "https://example.com/steal" }, dependencies),
    /Refusing to send a Microsoft Graph token/,
  );
  assert.equal(state.fetchCalls, 0);
}

process.stdout.write("graph_request.mjs tests passed\n");
