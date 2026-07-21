import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type NotificationData = Record<string, unknown>;

type RequestBody = {
  token?: string;
  tokens?: string[];
  title: string;
  body: string;
  data?: NotificationData;
};

const jsonHeaders = {
  "Content-Type": "application/json",
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function createJsonResponse(
  data: unknown,
  status = 200,
) {
  return new Response(
    JSON.stringify(data),
    {
      status,
      headers: {
        ...jsonHeaders,
        ...corsHeaders,
      },
    },
  );
}

function base64UrlEncode(
  input: ArrayBuffer | string,
) {
  const bytes =
    typeof input === "string"
      ? new TextEncoder().encode(input)
      : new Uint8Array(input);

  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function normalizeTokens(
  token?: string,
  tokens?: string[],
) {
  const tokenSet = new Set<string>();

  if (
    typeof token === "string" &&
    token.trim().length > 0
  ) {
    tokenSet.add(token.trim());
  }

  if (Array.isArray(tokens)) {
    for (const currentToken of tokens) {
      if (
        typeof currentToken === "string" &&
        currentToken.trim().length > 0
      ) {
        tokenSet.add(
          currentToken.trim(),
        );
      }
    }
  }

  return Array.from(tokenSet);
}

function normalizeData(
  data?: NotificationData,
): Record<string, string> {
  if (!data) {
    return {};
  }

  const normalizedData: Record<string, string> = {};

  for (
    const [key, value] of Object.entries(data)
  ) {
    if (value === null || value === undefined) {
      continue;
    }

    normalizedData[key] = String(value);
  }

  return normalizedData;
}

async function getAccessToken() {
  const clientEmail =
    Deno.env.get("FIREBASE_CLIENT_EMAIL");

  const privateKeyRaw =
    Deno.env.get("FIREBASE_PRIVATE_KEY");

  if (!clientEmail || !privateKeyRaw) {
    throw new Error(
      "Firebase credentials are missing.",
    );
  }

  const privateKey =
    privateKeyRaw.replace(/\\n/g, "\n");

  const now =
    Math.floor(Date.now() / 1000);

  const header = {
    alg: "RS256",
    typ: "JWT",
  };

  const claimSet = {
    iss: clientEmail,
    scope:
      "https://www.googleapis.com/auth/firebase.messaging",
    aud:
      "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const unsignedJwt =
    `${base64UrlEncode(
      JSON.stringify(header),
    )}.${base64UrlEncode(
      JSON.stringify(claimSet),
    )}`;

  const keyData = privateKey
    .replace(
      "-----BEGIN PRIVATE KEY-----",
      "",
    )
    .replace(
      "-----END PRIVATE KEY-----",
      "",
    )
    .replace(/\s/g, "");

  const binaryDer =
    Uint8Array.from(
      atob(keyData),
      (character) =>
        character.charCodeAt(0),
    );

  const cryptoKey =
    await crypto.subtle.importKey(
      "pkcs8",
      binaryDer.buffer,
      {
        name: "RSASSA-PKCS1-v1_5",
        hash: "SHA-256",
      },
      false,
      ["sign"],
    );

  const signature =
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      cryptoKey,
      new TextEncoder().encode(
        unsignedJwt,
      ),
    );

  const signedJwt =
    `${unsignedJwt}.${base64UrlEncode(
      signature,
    )}`;

  const tokenResponse =
    await fetch(
      "https://oauth2.googleapis.com/token",
      {
        method: "POST",
        headers: {
          "Content-Type":
            "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({
          grant_type:
            "urn:ietf:params:oauth:grant-type:jwt-bearer",
          assertion: signedJwt,
        }),
      },
    );

  const tokenData =
    await tokenResponse.json();

  if (!tokenResponse.ok) {
    throw new Error(
      `Failed to get access token: ${
        JSON.stringify(tokenData)
      }`,
    );
  }

  return tokenData.access_token as string;
}

async function sendToDevice({
  projectId,
  accessToken,
  token,
  title,
  body,
  data,
}: {
  projectId: string;
  accessToken: string;
  token: string;
  title: string;
  body: string;
  data: Record<string, string>;
}) {
  try {
    const message: Record<string, unknown> = {
      token,
      notification: {
        title,
        body,
      },
      android: {
        priority: "HIGH",
        notification: {
          channel_id: "default",
          sound: "default",
        },
      },
    };

    if (Object.keys(data).length > 0) {
      message.data = data;
    }

    const fcmResponse =
      await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization:
              `Bearer ${accessToken}`,
            "Content-Type":
              "application/json",
          },
          body: JSON.stringify({
            message,
          }),
        },
      );

    const responseText =
      await fcmResponse.text();

    let result: unknown = responseText;

    try {
result =
  responseText.length === 0
    ? {}
    : JSON.parse(responseText);
    } catch (_) {
      result = responseText;
    }

    return {
      success: fcmResponse.ok,
      status: fcmResponse.status,
      tokenEnding:
        token.length > 8
          ? token.slice(-8)
          : token,
      result,
    };
  } catch (error) {
    return {
      success: false,
      status: 500,
      tokenEnding:
        token.length > 8
          ? token.slice(-8)
          : token,
      error: String(error),
    };
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(
      "ok",
      {
        headers: corsHeaders,
      },
    );
  }

  if (request.method !== "POST") {
    return createJsonResponse(
      {
        error:
          "Only POST method is allowed.",
      },
      405,
    );
  }

  try {
    const requestBody =
      await request.json() as RequestBody;

    const {
      token,
      tokens,
      title,
      body,
      data,
    } = requestBody;

    const targetTokens =
      normalizeTokens(token, tokens);

if (
  !title ||
  title.trim().length === 0 ||
  !body ||
  body.trim().length === 0
) {
      return createJsonResponse(
        {
          error:
            "title and body are required.",
        },
        400,
      );
    }

    if (targetTokens.length === 0) {
      return createJsonResponse(
        {
          error:
            "At least one token is required.",
        },
        400,
      );
    }

    const projectId =
      Deno.env.get(
        "FIREBASE_PROJECT_ID",
      );

    if (!projectId) {
      throw new Error(
        "FIREBASE_PROJECT_ID is missing.",
      );
    }

    const accessToken =
      await getAccessToken();

    const normalizedData =
      normalizeData(data);

    const results =
      await Promise.all(
        targetTokens.map(
          (currentToken) =>
            sendToDevice({
              projectId,
              accessToken,
              token: currentToken,
              title: title.trim(),
              body: body.trim(),
              data: normalizedData,
            }),
        ),
      );

const successCount =
  results.filter(
    (result) =>
      result.success === true,
  ).length;

    const failureCount =
      results.length - successCount;

    return createJsonResponse({
      success: successCount > 0,
      totalDevices:
        targetTokens.length,
      successCount,
      failureCount,
      results,
    });
  } catch (error) {
    console.error(
      "send-fcm error:",
      error,
    );

    return createJsonResponse(
      {
        success: false,
        error: String(error),
      },
      500,
    );
  }
});