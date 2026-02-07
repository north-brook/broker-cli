export type ProviderId = "anthropic" | "openai" | "google";

export type SkillId = "xApi" | "braveSearchApi";

export type GatewayMode = "paper" | "live";

export type SkillEntry = {
  apiKey: string;
};

export type WizardConfig = {
  aiProvider: {
    provider: ProviderId;
    apiKey: string;
    model: string;
  };
  skills: Partial<Record<SkillId, SkillEntry>>;
  ibkrUsername: string;
  ibkrPassword: string;
  ibkrGatewayMode: GatewayMode;
  ibkrAutoLogin: boolean;
};
