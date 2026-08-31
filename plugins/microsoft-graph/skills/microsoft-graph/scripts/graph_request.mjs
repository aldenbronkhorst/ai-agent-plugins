import { createHash } from "node:crypto";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";
import process from "node:process";
import { pathToFileURL } from "node:url";

const GRAPH_POWERSHELL_CLIENT_ID = "14d82eec-204b-4c2f-b7e8-296a70dab67e";

const CLOUDS = {
  global: {
    authority: "https://login.microsoftonline.com",
    graph: "https://graph.microsoft.com",
  },
  usgov: {
    authority: "https://login.microsoftonline.us",
    graph: "https://graph.microsoft.us",
  },
  usgovdod: {
    authority: "https://login.microsoftonline.us",
    graph: "https://dod-graph.microsoft.us",
  },
  china: {
    authority: "https://login.chinacloudapi.cn",
    graph: "https://microsoftgraph.chinacloudapi.cn",
  },
};

function parseArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--force-sign-in") {
      options.forceSignIn = true;
      continue;
    }
    if (!argument.startsWith("--")) {
      throw new Error(`Unexpected argument: ${argument}`);
    }
    const value = argv[index + 1];
    if (value === undefined) {
      throw new Error(`Missing value for ${argument}`);
    }
    options[argument.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = value;
    index += 1;
  }
  return options;
}

function requireOption(options, name) {
  const value = options[name];
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`Missing required option --${name.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)}`);
  }
  return value.trim();
}

function isInteractionRequired(error) {
  const code = String(error?.errorCode ?? "").toLowerCase();
  return (
    error?.name === "InteractionRequiredAuthError" ||
    [
      "interaction_required",
      "login_required",
      "consent_required",
      "invalid_grant",
      "no_tokens_found",
      "no_account_in_silent_request",
    ].includes(code)
  );
}

function getRequestUrl(uri, graphOrigin) {
  const requestUrl = new URL(uri, `${graphOrigin}/`);
  if (requestUrl.origin.toLowerCase() !== graphOrigin.toLowerCase()) {
    throw new Error(`Refusing to send a Microsoft Graph token to non-Graph host '${requestUrl.host}'.`);
  }
  return requestUrl;
}

export async function runGraphRequest(options, dependencies) {
  const account = requireOption(options, "account");
  const method = requireOption(options, "method").toUpperCase();
  const uri = requireOption(options, "uri");
  const stateDirectory = requireOption(options, "stateDir");
  const tenantId = (options.tenantId || "common").trim();
  const environmentName = (options.environment || "Global").toLowerCase();
  const cloud = CLOUDS[environmentName];
  if (!cloud) {
    throw new Error(`Unsupported Microsoft Graph environment '${options.environment}'.`);
  }
  if (!new Set(["GET", "POST", "PUT", "PATCH", "DELETE"]).has(method)) {
    throw new Error(`Unsupported HTTP method '${method}'.`);
  }

  const scopes = JSON.parse(options.scopesJson || '["User.Read"]');
  if (!Array.isArray(scopes) || scopes.length === 0 || scopes.some((scope) => typeof scope !== "string" || !scope.trim())) {
    throw new Error("Scopes must be a non-empty JSON array of strings.");
  }

  const cacheKey = createHash("sha256")
    .update(`${account.toLowerCase()}\n${tenantId.toLowerCase()}\n${environmentName}`)
    .digest("hex");
  const cacheDirectory = path.join(stateDirectory, "accounts");
  const cachePath = path.join(cacheDirectory, `${cacheKey}.cache`);
  const serviceName = "ai-agent-plugins.microsoft-graph";

  const { PublicClientApplication } = dependencies.msalNode;
  const {
    DataProtectionScope,
    PersistenceCreator,
    PersistenceCachePlugin,
  } = dependencies.msalExtensions;

  const persistence = await PersistenceCreator.createPersistence({
    cachePath,
    dataProtectionScope: DataProtectionScope.CurrentUser,
    serviceName,
    accountName: cacheKey,
    usePlaintextFileOnLinux: false,
  });
  if (options.forceSignIn) {
    await persistence.delete();
  }

  const application = new PublicClientApplication({
    auth: {
      clientId: GRAPH_POWERSHELL_CLIENT_ID,
      authority: `${cloud.authority}/${tenantId}`,
    },
    cache: {
      cachePlugin: new PersistenceCachePlugin(persistence, {
        retryNumber: 100,
        retryDelay: 50,
      }),
    },
  });

  const cachedAccounts = await application.getAllAccounts();
  const cachedAccount = cachedAccounts.find(
    (candidate) => String(candidate.username || "").toLowerCase() === account.toLowerCase(),
  );

  let authenticationResult;
  if (cachedAccount && !options.forceSignIn) {
    try {
      authenticationResult = await application.acquireTokenSilent({
        account: cachedAccount,
        scopes,
      });
    } catch (error) {
      if (!isInteractionRequired(error)) {
        throw error;
      }
    }
  }

  if (!authenticationResult) {
    authenticationResult = await application.acquireTokenByDeviceCode({
      scopes,
      deviceCodeCallback: (response) => {
        process.stderr.write(`${response.message}\n`);
      },
    });
  }
  if (!authenticationResult?.accessToken || !authenticationResult.account) {
    throw new Error("Microsoft authentication completed without returning an account and access token.");
  }

  const authenticatedAccount = String(authenticationResult.account.username || "");
  if (authenticatedAccount.toLowerCase() !== account.toLowerCase()) {
    await persistence.delete();
    throw new Error(
      `Microsoft authenticated '${authenticatedAccount || "an unknown account"}' instead of '${account}'. ` +
        "Run again and select the requested identity on Microsoft's device-login page.",
    );
  }

  const headers = options.headersJson ? JSON.parse(options.headersJson) : {};
  if (!headers || Array.isArray(headers) || typeof headers !== "object") {
    throw new Error("HeadersJson must be a JSON object.");
  }
  for (const headerName of Object.keys(headers)) {
    if (headerName.toLowerCase() === "authorization") {
      throw new Error("Authorization headers are managed by the helper and cannot be overridden.");
    }
  }
  headers.Authorization = `Bearer ${authenticationResult.accessToken}`;

  let body;
  if (options.bodyJson) {
    JSON.parse(options.bodyJson);
    body = options.bodyJson;
    if (!Object.keys(headers).some((name) => name.toLowerCase() === "content-type")) {
      headers["Content-Type"] = "application/json";
    }
  }

  const response = await dependencies.fetchImpl(getRequestUrl(uri, cloud.graph), {
    method,
    headers,
    body,
    redirect: "error",
    signal: AbortSignal.timeout(120_000),
  });
  const responseBytes = Buffer.from(await response.arrayBuffer());
  if (!response.ok) {
    const detail = responseBytes.toString("utf8").slice(0, 4_000);
    throw new Error(`Microsoft Graph request failed with HTTP ${response.status}: ${detail}`);
  }

  if (options.outputFilePath) {
    await writeFile(options.outputFilePath, responseBytes);
    return null;
  }

  const text = responseBytes.toString("utf8");
  if (!text) {
    return null;
  }
  const contentType = response.headers.get("content-type") || "";
  if (contentType.includes("json")) {
    return JSON.stringify(JSON.parse(text), null, 2);
  }
  return text;
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const runtimeDirectory = requireOption(options, "runtimeDir");
  const runtimeRequire = createRequire(path.join(runtimeDirectory, "package.json"));
  const result = await runGraphRequest(options, {
    msalNode: runtimeRequire("@azure/msal-node"),
    msalExtensions: runtimeRequire("@azure/msal-node-extensions"),
    fetchImpl: globalThis.fetch,
  });
  if (result !== null && result !== undefined) {
    process.stdout.write(`${result}\n`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((error) => {
    process.stderr.write(`${error?.message || String(error)}\n`);
    process.exitCode = 1;
  });
}
