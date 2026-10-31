// The sheet check against the catalog shape T3 returns today, where an option
// lists its choices as `values`, with booleans as real booleans. This lives in
// its own file so that merging upstream's t3-sheet.test.mjs never conflicts.
import { describe, expect, test } from "bun:test";

import { loadModels } from "../tools/generate.mjs";
import { checkSheet, parseSheet } from "../plugins/pstack/skills/setup-pstack/scripts/t3-sheet.mjs";

const catalog = {
  providers: [
    {
      providerInstanceId: "claudeAgent",
      canRunChildTask: true,
      canRunCrossProviderChildTask: true,
      models: [
        {
          id: "claude-opus-5-5",
          options: [
            { id: "effort", values: ["low", "medium", "high", "xhigh", "max"], default: "medium" },
            { id: "fastMode", values: [false, true] },
          ],
        },
      ],
    },
  ],
};

const { roles, tiers: defaults } = loadModels();
const swarmWorkers = roles.filter((role) => role.role === "swarm workers");
const check = (options) =>
  checkSheet(parseSheet(`swarm workers: claudeAgent/claude-opus-5-5 ${options}\n`), { roles: swarmWorkers, defaults, catalog });

describe("checkSheet with a catalog that lists `values`", () => {
  test("accepts a listed value", () => {
    expect(check("effort=xhigh")).toEqual([]);
  });

  test("rejects an unlisted value and names the choices", () => {
    expect(check("effort=bogus")).toEqual([
      "swarm workers: claudeAgent/claude-opus-5-5: effort=bogus is not one of low, medium, high, xhigh, max",
    ]);
  });

  test("reads boolean values as the text a sheet writes", () => {
    expect(check("fastMode=true")).toEqual([]);
    expect(check("fastMode=maybe")).toEqual([
      "swarm workers: claudeAgent/claude-opus-5-5: fastMode=maybe is not one of false, true",
    ]);
  });

  test("still names a missing option", () => {
    expect(check("thinking=high")).toEqual([
      'swarm workers: claudeAgent/claude-opus-5-5: no option "thinking" (has effort, fastMode)',
    ]);
  });
});
