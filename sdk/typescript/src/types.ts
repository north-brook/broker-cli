export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonObject | JsonValue[];
export interface JsonObject {
  [key: string]: JsonValue;
}

export interface ErrorResponse {
  code: string;
  message: string;
  details?: Record<string, JsonValue>;
  suggestion?: string | null;
}

export interface RequestEnvelope {
  request_id: string;
  command: string;
  params: Record<string, JsonValue>;
  stream: boolean;
  source: string;
}

export interface ResponseEnvelope {
  request_id: string;
  ok: boolean;
  data?: JsonValue;
  error?: ErrorResponse;
}

export interface EventEnvelope {
  request_id?: string | null;
  topic: string;
  data: Record<string, JsonValue>;
}

export interface GatewayConfig {
  host: string;
  port: number;
  client_id: number;
  auto_reconnect: boolean;
  reconnect_backoff_max: number;
}

export interface LoggingConfig {
  level: string;
  audit_db: string;
  log_file: string;
  max_log_size_mb: number;
}

export interface AgentConfig {
  heartbeat_timeout_seconds: number;
  on_heartbeat_timeout: string;
  default_output: string;
}

export interface OutputConfig {
  default_format: string;
  timezone: string;
}

export interface RuntimeConfig {
  socket_path: string;
  pid_file: string;
  request_timeout_seconds: number;
}

export interface AppConfig {
  gateway: GatewayConfig;
  logging: LoggingConfig;
  agent: AgentConfig;
  output: OutputConfig;
  runtime: RuntimeConfig;
}

export type RequestParams = Record<string, JsonValue>;
