# Chain Forge — session continuity

Stages are workflow metadata used to select context payloads; they do not
change instruction priority or safety boundaries.

Preserve the task goal, decisions, constraints, completed work, failed attempts,
and unresolved steps across long sessions and compaction. Never rewrite prior
turns or remove refusals and limitations from the conversation record.

Stage and telemetry state are stored under the Chain Forge state directory.
The heartbeat log records plugin hook activity; it is not proof that every
injection or downstream operation succeeded.
