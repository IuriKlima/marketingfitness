export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      academy_facts: {
        Row: {
          confirmed_at: string
          facts: Json
          id: string
          onboarding_id: string
          organization_id: string
          unit_id: string
        }
        Insert: {
          confirmed_at?: string
          facts: Json
          id?: string
          onboarding_id: string
          organization_id: string
          unit_id: string
        }
        Update: {
          confirmed_at?: string
          facts?: Json
          id?: string
          onboarding_id?: string
          organization_id?: string
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "academy_facts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "academy_facts_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "academy_facts_organization_id_unit_id_onboarding_id_fkey"
            columns: ["organization_id", "unit_id", "onboarding_id"]
            isOneToOne: false
            referencedRelation: "onboarding_versions"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      ai_assistant_configs: {
        Row: {
          assistant_name: string
          business_hours: Json
          circuit_open_until: string | null
          commercial_rules: Json
          daily_budget_cents: number
          enabled: boolean
          id: string
          max_messages_per_conversation: number
          monthly_budget_cents: number
          objectives: Json
          organization_id: string
          qualification_questions: Json
          queue_id: string | null
          tone: string
          transfer_triggers: Json
          unit_id: string
          updated_at: string
          updated_by: string
          welcome_messages: Json
        }
        Insert: {
          assistant_name?: string
          business_hours?: Json
          circuit_open_until?: string | null
          commercial_rules?: Json
          daily_budget_cents?: number
          enabled?: boolean
          id?: string
          max_messages_per_conversation?: number
          monthly_budget_cents?: number
          objectives?: Json
          organization_id: string
          qualification_questions?: Json
          queue_id?: string | null
          tone?: string
          transfer_triggers?: Json
          unit_id: string
          updated_at?: string
          updated_by: string
          welcome_messages?: Json
        }
        Update: {
          assistant_name?: string
          business_hours?: Json
          circuit_open_until?: string | null
          commercial_rules?: Json
          daily_budget_cents?: number
          enabled?: boolean
          id?: string
          max_messages_per_conversation?: number
          monthly_budget_cents?: number
          objectives?: Json
          organization_id?: string
          qualification_questions?: Json
          queue_id?: string | null
          tone?: string
          transfer_triggers?: Json
          unit_id?: string
          updated_at?: string
          updated_by?: string
          welcome_messages?: Json
        }
        Relationships: [
          {
            foreignKeyName: "ai_assistant_configs_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: true
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "ai_assistant_configs_organization_id_unit_id_queue_id_fkey"
            columns: ["organization_id", "unit_id", "queue_id"]
            isOneToOne: false
            referencedRelation: "conversation_queues"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      ai_runs: {
        Row: {
          completed_at: string | null
          conversation_id: string | null
          correlation_id: string
          error_code: string | null
          estimated_cost_cents: number
          id: string
          input_tokens: number
          latency_ms: number | null
          model: string
          organization_id: string
          output_tokens: number
          provider: string
          result_code: string | null
          sources_used: Json
          started_at: string
          status: Database["public"]["Enums"]["ai_run_status"]
          transfer_reason: string | null
          unit_id: string
        }
        Insert: {
          completed_at?: string | null
          conversation_id?: string | null
          correlation_id?: string
          error_code?: string | null
          estimated_cost_cents?: number
          id?: string
          input_tokens?: number
          latency_ms?: number | null
          model: string
          organization_id: string
          output_tokens?: number
          provider: string
          result_code?: string | null
          sources_used?: Json
          started_at?: string
          status?: Database["public"]["Enums"]["ai_run_status"]
          transfer_reason?: string | null
          unit_id: string
        }
        Update: {
          completed_at?: string | null
          conversation_id?: string | null
          correlation_id?: string
          error_code?: string | null
          estimated_cost_cents?: number
          id?: string
          input_tokens?: number
          latency_ms?: number | null
          model?: string
          organization_id?: string
          output_tokens?: number
          provider?: string
          result_code?: string | null
          sources_used?: Json
          started_at?: string
          status?: Database["public"]["Enums"]["ai_run_status"]
          transfer_reason?: string | null
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_runs_organization_id_unit_id_conversation_id_fkey"
            columns: ["organization_id", "unit_id", "conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
          {
            foreignKeyName: "ai_runs_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      ai_tool_calls: {
        Row: {
          ai_run_id: string
          arguments_sha256: string
          created_at: string
          id: string
          organization_id: string
          result_code: string | null
          status: string
          tool_name: string
          unit_id: string
        }
        Insert: {
          ai_run_id: string
          arguments_sha256: string
          created_at?: string
          id?: string
          organization_id: string
          result_code?: string | null
          status: string
          tool_name: string
          unit_id: string
        }
        Update: {
          ai_run_id?: string
          arguments_sha256?: string
          created_at?: string
          id?: string
          organization_id?: string
          result_code?: string | null
          status?: string
          tool_name?: string
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_tool_calls_organization_id_unit_id_ai_run_id_fkey"
            columns: ["organization_id", "unit_id", "ai_run_id"]
            isOneToOne: false
            referencedRelation: "ai_runs"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
          {
            foreignKeyName: "ai_tool_calls_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      ai_usage_daily: {
        Row: {
          estimated_cost_cents: number
          input_tokens: number
          organization_id: string
          output_tokens: number
          run_count: number
          unit_id: string
          usage_date: string
        }
        Insert: {
          estimated_cost_cents?: number
          input_tokens?: number
          organization_id: string
          output_tokens?: number
          run_count?: number
          unit_id: string
          usage_date: string
        }
        Update: {
          estimated_cost_cents?: number
          input_tokens?: number
          organization_id?: string
          output_tokens?: number
          run_count?: number
          unit_id?: string
          usage_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_usage_daily_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      audit_events: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          entity_id: string
          id: string
          organization_id: string
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          entity_id: string
          id?: string
          organization_id: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          entity_id?: string
          id?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "audit_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      channel_connections: {
        Row: {
          base_url: string | null
          capabilities: Json
          created_at: string
          created_by: string
          external_instance: string | null
          health: Json
          id: string
          last_error_code: string | null
          last_synced_at: string | null
          name: string
          organization_id: string
          provider: Database["public"]["Enums"]["messaging_provider"]
          secret_id: string | null
          status: Database["public"]["Enums"]["channel_connection_status"]
          unit_id: string
          updated_at: string
          webhook_secret_id: string | null
          webhook_token_hash: string
        }
        Insert: {
          base_url?: string | null
          capabilities?: Json
          created_at?: string
          created_by: string
          external_instance?: string | null
          health?: Json
          id?: string
          last_error_code?: string | null
          last_synced_at?: string | null
          name: string
          organization_id: string
          provider: Database["public"]["Enums"]["messaging_provider"]
          secret_id?: string | null
          status?: Database["public"]["Enums"]["channel_connection_status"]
          unit_id: string
          updated_at?: string
          webhook_secret_id?: string | null
          webhook_token_hash: string
        }
        Update: {
          base_url?: string | null
          capabilities?: Json
          created_at?: string
          created_by?: string
          external_instance?: string | null
          health?: Json
          id?: string
          last_error_code?: string | null
          last_synced_at?: string | null
          name?: string
          organization_id?: string
          provider?: Database["public"]["Enums"]["messaging_provider"]
          secret_id?: string | null
          status?: Database["public"]["Enums"]["channel_connection_status"]
          unit_id?: string
          updated_at?: string
          webhook_secret_id?: string | null
          webhook_token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "channel_connections_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      conversation_assignment_history: {
        Row: {
          actor_id: string
          conversation_id: string
          created_at: string
          from_state: Database["public"]["Enums"]["conversation_state"]
          from_user_id: string | null
          id: string
          organization_id: string
          reason: string
          to_state: Database["public"]["Enums"]["conversation_state"]
          to_user_id: string | null
          unit_id: string
        }
        Insert: {
          actor_id: string
          conversation_id: string
          created_at?: string
          from_state: Database["public"]["Enums"]["conversation_state"]
          from_user_id?: string | null
          id?: string
          organization_id: string
          reason: string
          to_state: Database["public"]["Enums"]["conversation_state"]
          to_user_id?: string | null
          unit_id: string
        }
        Update: {
          actor_id?: string
          conversation_id?: string
          created_at?: string
          from_state?: Database["public"]["Enums"]["conversation_state"]
          from_user_id?: string | null
          id?: string
          organization_id?: string
          reason?: string
          to_state?: Database["public"]["Enums"]["conversation_state"]
          to_user_id?: string | null
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversation_assignment_histo_organization_id_unit_id_conv_fkey"
            columns: ["organization_id", "unit_id", "conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      conversation_participants: {
        Row: {
          contact_id: string | null
          conversation_id: string
          created_at: string
          external_address: string | null
          id: string
          organization_id: string
          participant_kind: string
          unit_id: string
          user_id: string | null
        }
        Insert: {
          contact_id?: string | null
          conversation_id: string
          created_at?: string
          external_address?: string | null
          id?: string
          organization_id: string
          participant_kind: string
          unit_id: string
          user_id?: string | null
        }
        Update: {
          contact_id?: string | null
          conversation_id?: string
          created_at?: string
          external_address?: string | null
          id?: string
          organization_id?: string
          participant_kind?: string
          unit_id?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "conversation_participants_organization_id_contact_id_fkey"
            columns: ["organization_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "crm_contacts"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "conversation_participants_organization_id_unit_id_conversa_fkey"
            columns: ["organization_id", "unit_id", "conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      conversation_queues: {
        Row: {
          active: boolean
          id: string
          name: string
          organization_id: string
          priority: number
          sla_first_response_seconds: number
          unit_id: string
        }
        Insert: {
          active?: boolean
          id?: string
          name: string
          organization_id: string
          priority?: number
          sla_first_response_seconds?: number
          unit_id: string
        }
        Update: {
          active?: boolean
          id?: string
          name?: string
          organization_id?: string
          priority?: number
          sla_first_response_seconds?: number
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversation_queues_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      conversations: {
        Row: {
          assigned_to: string | null
          assignment_lease_until: string | null
          channel_connection_id: string
          closed_at: string | null
          contact_id: string
          created_at: string
          external_thread_id: string
          first_response_due_at: string | null
          id: string
          last_message_at: string
          organization_id: string
          priority: number
          queue_id: string | null
          state: Database["public"]["Enums"]["conversation_state"]
          subject: string | null
          unit_id: string
          unread_count: number
          updated_at: string
        }
        Insert: {
          assigned_to?: string | null
          assignment_lease_until?: string | null
          channel_connection_id: string
          closed_at?: string | null
          contact_id: string
          created_at?: string
          external_thread_id: string
          first_response_due_at?: string | null
          id?: string
          last_message_at?: string
          organization_id: string
          priority?: number
          queue_id?: string | null
          state?: Database["public"]["Enums"]["conversation_state"]
          subject?: string | null
          unit_id: string
          unread_count?: number
          updated_at?: string
        }
        Update: {
          assigned_to?: string | null
          assignment_lease_until?: string | null
          channel_connection_id?: string
          closed_at?: string | null
          contact_id?: string
          created_at?: string
          external_thread_id?: string
          first_response_due_at?: string | null
          id?: string
          last_message_at?: string
          organization_id?: string
          priority?: number
          queue_id?: string | null
          state?: Database["public"]["Enums"]["conversation_state"]
          subject?: string | null
          unit_id?: string
          unread_count?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversations_organization_id_contact_id_unit_id_fkey"
            columns: ["organization_id", "contact_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "crm_contact_units"
            referencedColumns: ["organization_id", "contact_id", "unit_id"]
          },
          {
            foreignKeyName: "conversations_organization_id_unit_id_channel_connection_i_fkey"
            columns: ["organization_id", "unit_id", "channel_connection_id"]
            isOneToOne: false
            referencedRelation: "channel_connections"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
          {
            foreignKeyName: "conversations_organization_id_unit_id_queue_id_fkey"
            columns: ["organization_id", "unit_id", "queue_id"]
            isOneToOne: false
            referencedRelation: "conversation_queues"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      crm_activities: {
        Row: {
          activity_type: string
          actor_id: string | null
          contact_id: string
          id: string
          metadata: Json
          occurred_at: string
          opportunity_id: string | null
          organization_id: string
          summary: string
          unit_id: string
        }
        Insert: {
          activity_type: string
          actor_id?: string | null
          contact_id: string
          id?: string
          metadata?: Json
          occurred_at?: string
          opportunity_id?: string | null
          organization_id: string
          summary: string
          unit_id: string
        }
        Update: {
          activity_type?: string
          actor_id?: string | null
          contact_id?: string
          id?: string
          metadata?: Json
          occurred_at?: string
          opportunity_id?: string | null
          organization_id?: string
          summary?: string
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_activities_organization_id_contact_id_fkey"
            columns: ["organization_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "crm_contacts"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "crm_activities_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "crm_activities_organization_id_unit_id_opportunity_id_fkey"
            columns: ["organization_id", "unit_id", "opportunity_id"]
            isOneToOne: false
            referencedRelation: "crm_opportunities"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      crm_appointment_events: {
        Row: {
          actor_id: string
          appointment_id: string
          created_at: string
          from_status:
            | Database["public"]["Enums"]["crm_appointment_status"]
            | null
          id: string
          organization_id: string
          reason: string | null
          to_status: Database["public"]["Enums"]["crm_appointment_status"]
          unit_id: string
        }
        Insert: {
          actor_id: string
          appointment_id: string
          created_at?: string
          from_status?:
            | Database["public"]["Enums"]["crm_appointment_status"]
            | null
          id?: string
          organization_id: string
          reason?: string | null
          to_status: Database["public"]["Enums"]["crm_appointment_status"]
          unit_id: string
        }
        Update: {
          actor_id?: string
          appointment_id?: string
          created_at?: string
          from_status?:
            | Database["public"]["Enums"]["crm_appointment_status"]
            | null
          id?: string
          organization_id?: string
          reason?: string | null
          to_status?: Database["public"]["Enums"]["crm_appointment_status"]
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_appointment_events_organization_id_unit_id_appointment_fkey"
            columns: ["organization_id", "unit_id", "appointment_id"]
            isOneToOne: false
            referencedRelation: "crm_appointments"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      crm_appointments: {
        Row: {
          contact_id: string
          created_at: string
          created_by: string
          ends_at: string
          id: string
          idempotency_key: string
          kind: string
          notes: string | null
          opportunity_id: string | null
          organization_id: string
          responsible_id: string
          starts_at: string
          status: Database["public"]["Enums"]["crm_appointment_status"]
          unit_id: string
          updated_at: string
        }
        Insert: {
          contact_id: string
          created_at?: string
          created_by: string
          ends_at: string
          id?: string
          idempotency_key: string
          kind: string
          notes?: string | null
          opportunity_id?: string | null
          organization_id: string
          responsible_id: string
          starts_at: string
          status?: Database["public"]["Enums"]["crm_appointment_status"]
          unit_id: string
          updated_at?: string
        }
        Update: {
          contact_id?: string
          created_at?: string
          created_by?: string
          ends_at?: string
          id?: string
          idempotency_key?: string
          kind?: string
          notes?: string | null
          opportunity_id?: string | null
          organization_id?: string
          responsible_id?: string
          starts_at?: string
          status?: Database["public"]["Enums"]["crm_appointment_status"]
          unit_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_appointments_organization_id_contact_id_fkey"
            columns: ["organization_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "crm_contacts"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "crm_appointments_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "crm_appointments_organization_id_unit_id_opportunity_id_fkey"
            columns: ["organization_id", "unit_id", "opportunity_id"]
            isOneToOne: false
            referencedRelation: "crm_opportunities"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      crm_consents: {
        Row: {
          channel: string
          contact_id: string
          created_at: string
          granted_at: string | null
          id: string
          legal_basis: string
          organization_id: string
          proof: Json
          purpose: string
          revoked_at: string | null
          source: string
          valid_until: string | null
        }
        Insert: {
          channel: string
          contact_id: string
          created_at?: string
          granted_at?: string | null
          id?: string
          legal_basis: string
          organization_id: string
          proof?: Json
          purpose: string
          revoked_at?: string | null
          source: string
          valid_until?: string | null
        }
        Update: {
          channel?: string
          contact_id?: string
          created_at?: string
          granted_at?: string | null
          id?: string
          legal_basis?: string
          organization_id?: string
          proof?: Json
          purpose?: string
          revoked_at?: string | null
          source?: string
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "crm_consents_organization_id_contact_id_fkey"
            columns: ["organization_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "crm_contacts"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      crm_contact_identifiers: {
        Row: {
          contact_id: string
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["crm_identifier_kind"]
          normalized_value: string
          organization_id: string
          verified_at: string | null
        }
        Insert: {
          contact_id: string
          created_at?: string
          id?: string
          kind: Database["public"]["Enums"]["crm_identifier_kind"]
          normalized_value: string
          organization_id: string
          verified_at?: string | null
        }
        Update: {
          contact_id?: string
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["crm_identifier_kind"]
          normalized_value?: string
          organization_id?: string
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "crm_contact_identifiers_organization_id_contact_id_fkey"
            columns: ["organization_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "crm_contacts"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      crm_contact_tags: {
        Row: {
          contact_id: string
          created_at: string
          created_by: string
          organization_id: string
          tag_id: string
        }
        Insert: {
          contact_id: string
          created_at?: string
          created_by: string
          organization_id: string
          tag_id: string
        }
        Update: {
          contact_id?: string
          created_at?: string
          created_by?: string
          organization_id?: string
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_contact_tags_organization_id_contact_id_fkey"
            columns: ["organization_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "crm_contacts"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "crm_contact_tags_organization_id_tag_id_fkey"
            columns: ["organization_id", "tag_id"]
            isOneToOne: false
            referencedRelation: "crm_tags"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      crm_contact_units: {
        Row: {
          contact_id: string
          first_seen_at: string
          last_seen_at: string
          organization_id: string
          unit_id: string
        }
        Insert: {
          contact_id: string
          first_seen_at?: string
          last_seen_at?: string
          organization_id: string
          unit_id: string
        }
        Update: {
          contact_id?: string
          first_seen_at?: string
          last_seen_at?: string
          organization_id?: string
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_contact_units_organization_id_contact_id_fkey"
            columns: ["organization_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "crm_contacts"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "crm_contact_units_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      crm_contacts: {
        Row: {
          anonymized_at: string | null
          city: string | null
          created_at: string
          display_name: string
          id: string
          organization_id: string
          source: string | null
          updated_at: string
        }
        Insert: {
          anonymized_at?: string | null
          city?: string | null
          created_at?: string
          display_name: string
          id?: string
          organization_id: string
          source?: string | null
          updated_at?: string
        }
        Update: {
          anonymized_at?: string | null
          city?: string | null
          created_at?: string
          display_name?: string
          id?: string
          organization_id?: string
          source?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_contacts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      crm_notes: {
        Row: {
          author_id: string
          body: string
          contact_id: string
          created_at: string
          id: string
          organization_id: string
          unit_id: string
        }
        Insert: {
          author_id: string
          body: string
          contact_id: string
          created_at?: string
          id?: string
          organization_id: string
          unit_id: string
        }
        Update: {
          author_id?: string
          body?: string
          contact_id?: string
          created_at?: string
          id?: string
          organization_id?: string
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_notes_organization_id_contact_id_fkey"
            columns: ["organization_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "crm_contacts"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "crm_notes_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      crm_opportunities: {
        Row: {
          campaign: string | null
          contact_id: string
          created_at: string
          enrolled_at: string | null
          external_key: string | null
          id: string
          loss_reason: string | null
          lost_at: string | null
          organization_id: string
          owner_id: string | null
          pipeline_id: string
          source: string | null
          stage_id: string
          status: Database["public"]["Enums"]["crm_opportunity_status"]
          title: string
          unit_id: string
          updated_at: string
          value_cents: number | null
        }
        Insert: {
          campaign?: string | null
          contact_id: string
          created_at?: string
          enrolled_at?: string | null
          external_key?: string | null
          id?: string
          loss_reason?: string | null
          lost_at?: string | null
          organization_id: string
          owner_id?: string | null
          pipeline_id: string
          source?: string | null
          stage_id: string
          status?: Database["public"]["Enums"]["crm_opportunity_status"]
          title: string
          unit_id: string
          updated_at?: string
          value_cents?: number | null
        }
        Update: {
          campaign?: string | null
          contact_id?: string
          created_at?: string
          enrolled_at?: string | null
          external_key?: string | null
          id?: string
          loss_reason?: string | null
          lost_at?: string | null
          organization_id?: string
          owner_id?: string | null
          pipeline_id?: string
          source?: string | null
          stage_id?: string
          status?: Database["public"]["Enums"]["crm_opportunity_status"]
          title?: string
          unit_id?: string
          updated_at?: string
          value_cents?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "crm_opportunities_organization_id_contact_id_unit_id_fkey"
            columns: ["organization_id", "contact_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "crm_contact_units"
            referencedColumns: ["organization_id", "contact_id", "unit_id"]
          },
          {
            foreignKeyName: "crm_opportunities_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "crm_opportunities_organization_id_unit_id_pipeline_id_fkey"
            columns: ["organization_id", "unit_id", "pipeline_id"]
            isOneToOne: false
            referencedRelation: "crm_pipelines"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
          {
            foreignKeyName: "crm_opportunities_organization_id_unit_id_stage_id_fkey"
            columns: ["organization_id", "unit_id", "stage_id"]
            isOneToOne: false
            referencedRelation: "crm_pipeline_stages"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      crm_opportunity_stage_history: {
        Row: {
          actor_id: string
          created_at: string
          from_stage_id: string | null
          id: string
          idempotency_key: string
          opportunity_id: string
          organization_id: string
          reason: string | null
          to_stage_id: string
          unit_id: string
        }
        Insert: {
          actor_id: string
          created_at?: string
          from_stage_id?: string | null
          id?: string
          idempotency_key: string
          opportunity_id: string
          organization_id: string
          reason?: string | null
          to_stage_id: string
          unit_id: string
        }
        Update: {
          actor_id?: string
          created_at?: string
          from_stage_id?: string | null
          id?: string
          idempotency_key?: string
          opportunity_id?: string
          organization_id?: string
          reason?: string | null
          to_stage_id?: string
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_opportunity_stage_history_organization_id_unit_id_from_fkey"
            columns: ["organization_id", "unit_id", "from_stage_id"]
            isOneToOne: false
            referencedRelation: "crm_pipeline_stages"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
          {
            foreignKeyName: "crm_opportunity_stage_history_organization_id_unit_id_oppo_fkey"
            columns: ["organization_id", "unit_id", "opportunity_id"]
            isOneToOne: false
            referencedRelation: "crm_opportunities"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
          {
            foreignKeyName: "crm_opportunity_stage_history_organization_id_unit_id_to_s_fkey"
            columns: ["organization_id", "unit_id", "to_stage_id"]
            isOneToOne: false
            referencedRelation: "crm_pipeline_stages"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      crm_pipeline_stages: {
        Row: {
          active: boolean
          id: string
          name: string
          organization_id: string
          outcome: Database["public"]["Enums"]["crm_opportunity_status"] | null
          pipeline_id: string
          position: number
          unit_id: string
        }
        Insert: {
          active?: boolean
          id?: string
          name: string
          organization_id: string
          outcome?: Database["public"]["Enums"]["crm_opportunity_status"] | null
          pipeline_id: string
          position: number
          unit_id: string
        }
        Update: {
          active?: boolean
          id?: string
          name?: string
          organization_id?: string
          outcome?: Database["public"]["Enums"]["crm_opportunity_status"] | null
          pipeline_id?: string
          position?: number
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_pipeline_stages_organization_id_unit_id_pipeline_id_fkey"
            columns: ["organization_id", "unit_id", "pipeline_id"]
            isOneToOne: false
            referencedRelation: "crm_pipelines"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      crm_pipelines: {
        Row: {
          active: boolean
          created_at: string
          id: string
          name: string
          organization_id: string
          unit_id: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          id?: string
          name: string
          organization_id: string
          unit_id: string
        }
        Update: {
          active?: boolean
          created_at?: string
          id?: string
          name?: string
          organization_id?: string
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_pipelines_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      crm_tags: {
        Row: {
          color: string | null
          id: string
          name: string
          organization_id: string
        }
        Insert: {
          color?: string | null
          id?: string
          name: string
          organization_id: string
        }
        Update: {
          color?: string | null
          id?: string
          name?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_tags_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      crm_tasks: {
        Row: {
          assignee_id: string
          completed_at: string | null
          contact_id: string | null
          created_at: string
          created_by: string
          due_at: string
          id: string
          idempotency_key: string
          opportunity_id: string | null
          organization_id: string
          priority: Database["public"]["Enums"]["crm_task_priority"]
          remind_at: string | null
          status: Database["public"]["Enums"]["crm_task_status"]
          title: string
          unit_id: string
          updated_at: string
        }
        Insert: {
          assignee_id: string
          completed_at?: string | null
          contact_id?: string | null
          created_at?: string
          created_by: string
          due_at: string
          id?: string
          idempotency_key: string
          opportunity_id?: string | null
          organization_id: string
          priority?: Database["public"]["Enums"]["crm_task_priority"]
          remind_at?: string | null
          status?: Database["public"]["Enums"]["crm_task_status"]
          title: string
          unit_id: string
          updated_at?: string
        }
        Update: {
          assignee_id?: string
          completed_at?: string | null
          contact_id?: string | null
          created_at?: string
          created_by?: string
          due_at?: string
          id?: string
          idempotency_key?: string
          opportunity_id?: string | null
          organization_id?: string
          priority?: Database["public"]["Enums"]["crm_task_priority"]
          remind_at?: string | null
          status?: Database["public"]["Enums"]["crm_task_status"]
          title?: string
          unit_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_tasks_organization_id_contact_id_fkey"
            columns: ["organization_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "crm_contacts"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "crm_tasks_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "crm_tasks_organization_id_unit_id_opportunity_id_fkey"
            columns: ["organization_id", "unit_id", "opportunity_id"]
            isOneToOne: false
            referencedRelation: "crm_opportunities"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      data_retention_policies: {
        Row: {
          active: boolean
          data_class: string
          id: string
          organization_id: string
          retention_days: number
          unit_id: string | null
          updated_at: string
          updated_by: string
        }
        Insert: {
          active?: boolean
          data_class: string
          id?: string
          organization_id: string
          retention_days: number
          unit_id?: string | null
          updated_at?: string
          updated_by: string
        }
        Update: {
          active?: boolean
          data_class?: string
          id?: string
          organization_id?: string
          retention_days?: number
          unit_id?: string | null
          updated_at?: string
          updated_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "data_retention_policies_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "data_retention_policies_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      knowledge_chunks: {
        Row: {
          content: string
          created_at: string
          id: string
          lexical: unknown
          organization_id: string
          position: number
          unit_id: string | null
          version_id: string
        }
        Insert: {
          content: string
          created_at?: string
          id?: string
          lexical?: unknown
          organization_id: string
          position: number
          unit_id?: string | null
          version_id: string
        }
        Update: {
          content?: string
          created_at?: string
          id?: string
          lexical?: unknown
          organization_id?: string
          position?: number
          unit_id?: string | null
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_chunks_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "knowledge_chunks_organization_id_version_id_fkey"
            columns: ["organization_id", "version_id"]
            isOneToOne: false
            referencedRelation: "knowledge_document_versions"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      knowledge_document_versions: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          content_sha256: string
          created_at: string
          created_by: string
          document_id: string
          id: string
          indexing_status: Database["public"]["Enums"]["indexing_status"]
          organization_id: string
          status: Database["public"]["Enums"]["knowledge_status"]
          storage_path: string | null
          unit_id: string | null
          valid_from: string | null
          valid_until: string | null
          version: number
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          content_sha256: string
          created_at?: string
          created_by: string
          document_id: string
          id?: string
          indexing_status?: Database["public"]["Enums"]["indexing_status"]
          organization_id: string
          status?: Database["public"]["Enums"]["knowledge_status"]
          storage_path?: string | null
          unit_id?: string | null
          valid_from?: string | null
          valid_until?: string | null
          version: number
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          content_sha256?: string
          created_at?: string
          created_by?: string
          document_id?: string
          id?: string
          indexing_status?: Database["public"]["Enums"]["indexing_status"]
          organization_id?: string
          status?: Database["public"]["Enums"]["knowledge_status"]
          storage_path?: string | null
          unit_id?: string | null
          valid_from?: string | null
          valid_until?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_document_versions_organization_id_document_id_fkey"
            columns: ["organization_id", "document_id"]
            isOneToOne: false
            referencedRelation: "knowledge_documents"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "knowledge_document_versions_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      knowledge_documents: {
        Row: {
          created_at: string
          current_version: number
          id: string
          organization_id: string
          source_id: string
          title: string
          unit_id: string | null
        }
        Insert: {
          created_at?: string
          current_version?: number
          id?: string
          organization_id: string
          source_id: string
          title: string
          unit_id?: string | null
        }
        Update: {
          created_at?: string
          current_version?: number
          id?: string
          organization_id?: string
          source_id?: string
          title?: string
          unit_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_documents_organization_id_source_id_fkey"
            columns: ["organization_id", "source_id"]
            isOneToOne: false
            referencedRelation: "knowledge_sources"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "knowledge_documents_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      knowledge_sources: {
        Row: {
          created_at: string
          created_by: string
          id: string
          name: string
          organization_id: string
          origin: string | null
          source_kind: string
          status: Database["public"]["Enums"]["knowledge_status"]
          unit_id: string | null
          valid_from: string | null
          valid_until: string | null
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          name: string
          organization_id: string
          origin?: string | null
          source_kind: string
          status?: Database["public"]["Enums"]["knowledge_status"]
          unit_id?: string | null
          valid_from?: string | null
          valid_until?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          name?: string
          organization_id?: string
          origin?: string | null
          source_kind?: string
          status?: Database["public"]["Enums"]["knowledge_status"]
          unit_id?: string | null
          valid_from?: string | null
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_sources_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_sources_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      membership_roles: {
        Row: {
          membership_id: string
          organization_id: string
          role: Database["public"]["Enums"]["academy_role"]
        }
        Insert: {
          membership_id: string
          organization_id: string
          role: Database["public"]["Enums"]["academy_role"]
        }
        Update: {
          membership_id?: string
          organization_id?: string
          role?: Database["public"]["Enums"]["academy_role"]
        }
        Relationships: [
          {
            foreignKeyName: "membership_roles_organization_id_membership_id_fkey"
            columns: ["organization_id", "membership_id"]
            isOneToOne: false
            referencedRelation: "memberships"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      membership_units: {
        Row: {
          membership_id: string
          organization_id: string
          unit_id: string
        }
        Insert: {
          membership_id: string
          organization_id: string
          unit_id: string
        }
        Update: {
          membership_id?: string
          organization_id?: string
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "membership_units_organization_id_membership_id_fkey"
            columns: ["organization_id", "membership_id"]
            isOneToOne: false
            referencedRelation: "memberships"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "membership_units_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      memberships: {
        Row: {
          active: boolean
          all_units: boolean
          id: string
          organization_id: string
          user_id: string
        }
        Insert: {
          active?: boolean
          all_units?: boolean
          id?: string
          organization_id: string
          user_id: string
        }
        Update: {
          active?: boolean
          all_units?: boolean
          id?: string
          organization_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "memberships_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      message_attachments: {
        Row: {
          byte_size: number
          created_at: string
          filename: string
          id: string
          message_id: string
          mime_type: string
          organization_id: string
          sha256: string
          storage_path: string
          unit_id: string
        }
        Insert: {
          byte_size: number
          created_at?: string
          filename: string
          id?: string
          message_id: string
          mime_type: string
          organization_id: string
          sha256: string
          storage_path: string
          unit_id: string
        }
        Update: {
          byte_size?: number
          created_at?: string
          filename?: string
          id?: string
          message_id?: string
          mime_type?: string
          organization_id?: string
          sha256?: string
          storage_path?: string
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "message_attachments_organization_id_unit_id_message_id_fkey"
            columns: ["organization_id", "unit_id", "message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      message_delivery_events: {
        Row: {
          created_at: string
          error_code: string | null
          id: string
          message_id: string
          organization_id: string
          provider_at: string | null
          provider_event_id: string | null
          state: Database["public"]["Enums"]["message_delivery_state"]
          unit_id: string
        }
        Insert: {
          created_at?: string
          error_code?: string | null
          id?: string
          message_id: string
          organization_id: string
          provider_at?: string | null
          provider_event_id?: string | null
          state: Database["public"]["Enums"]["message_delivery_state"]
          unit_id: string
        }
        Update: {
          created_at?: string
          error_code?: string | null
          id?: string
          message_id?: string
          organization_id?: string
          provider_at?: string | null
          provider_event_id?: string | null
          state?: Database["public"]["Enums"]["message_delivery_state"]
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "message_delivery_events_organization_id_unit_id_message_id_fkey"
            columns: ["organization_id", "unit_id", "message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      messages: {
        Row: {
          author_kind: Database["public"]["Enums"]["message_author_kind"]
          author_user_id: string | null
          body: string | null
          channel_connection_id: string
          conversation_id: string
          created_at: string
          delivery_state: Database["public"]["Enums"]["message_delivery_state"]
          direction: Database["public"]["Enums"]["message_direction"]
          external_message_id: string | null
          id: string
          idempotency_key: string
          organization_id: string
          provider: Database["public"]["Enums"]["messaging_provider"]
          provider_at: string | null
          reply_to_message_id: string | null
          unit_id: string
        }
        Insert: {
          author_kind: Database["public"]["Enums"]["message_author_kind"]
          author_user_id?: string | null
          body?: string | null
          channel_connection_id: string
          conversation_id: string
          created_at?: string
          delivery_state?: Database["public"]["Enums"]["message_delivery_state"]
          direction: Database["public"]["Enums"]["message_direction"]
          external_message_id?: string | null
          id?: string
          idempotency_key: string
          organization_id: string
          provider: Database["public"]["Enums"]["messaging_provider"]
          provider_at?: string | null
          reply_to_message_id?: string | null
          unit_id: string
        }
        Update: {
          author_kind?: Database["public"]["Enums"]["message_author_kind"]
          author_user_id?: string | null
          body?: string | null
          channel_connection_id?: string
          conversation_id?: string
          created_at?: string
          delivery_state?: Database["public"]["Enums"]["message_delivery_state"]
          direction?: Database["public"]["Enums"]["message_direction"]
          external_message_id?: string | null
          id?: string
          idempotency_key?: string
          organization_id?: string
          provider?: Database["public"]["Enums"]["messaging_provider"]
          provider_at?: string | null
          reply_to_message_id?: string | null
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_organization_id_unit_id_channel_connection_id_fkey"
            columns: ["organization_id", "unit_id", "channel_connection_id"]
            isOneToOne: false
            referencedRelation: "channel_connections"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
          {
            foreignKeyName: "messages_organization_id_unit_id_conversation_id_fkey"
            columns: ["organization_id", "unit_id", "conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
          {
            foreignKeyName: "messages_organization_id_unit_id_reply_to_message_id_fkey"
            columns: ["organization_id", "unit_id", "reply_to_message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      onboarding_attachments: {
        Row: {
          byte_size: number
          created_at: string
          filename: string
          id: string
          mime_type: string
          onboarding_id: string
          organization_id: string
          storage_path: string
          unit_id: string
          uploaded_by: string
        }
        Insert: {
          byte_size: number
          created_at?: string
          filename: string
          id?: string
          mime_type: string
          onboarding_id: string
          organization_id: string
          storage_path: string
          unit_id: string
          uploaded_by: string
        }
        Update: {
          byte_size?: number
          created_at?: string
          filename?: string
          id?: string
          mime_type?: string
          onboarding_id?: string
          organization_id?: string
          storage_path?: string
          unit_id?: string
          uploaded_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "onboarding_attachments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "onboarding_attachments_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "onboarding_attachments_organization_id_unit_id_onboarding__fkey"
            columns: ["organization_id", "unit_id", "onboarding_id"]
            isOneToOne: false
            referencedRelation: "onboarding_versions"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      onboarding_field_definitions: {
        Row: {
          active: boolean
          description: string | null
          field_key: string
          field_type: Database["public"]["Enums"]["onboarding_field_type"]
          id: string
          label: string
          options: Json
          required: boolean
          schema_version: number
          scope: Database["public"]["Enums"]["onboarding_scope"]
          section: string
          sort_order: number
          validation: Json
        }
        Insert: {
          active?: boolean
          description?: string | null
          field_key: string
          field_type: Database["public"]["Enums"]["onboarding_field_type"]
          id?: string
          label: string
          options?: Json
          required?: boolean
          schema_version: number
          scope: Database["public"]["Enums"]["onboarding_scope"]
          section: string
          sort_order?: number
          validation?: Json
        }
        Update: {
          active?: boolean
          description?: string | null
          field_key?: string
          field_type?: Database["public"]["Enums"]["onboarding_field_type"]
          id?: string
          label?: string
          options?: Json
          required?: boolean
          schema_version?: number
          scope?: Database["public"]["Enums"]["onboarding_scope"]
          section?: string
          sort_order?: number
          validation?: Json
        }
        Relationships: []
      }
      onboarding_reviews: {
        Row: {
          created_at: string
          decision: Database["public"]["Enums"]["onboarding_review_decision"]
          id: string
          notes: string
          onboarding_id: string
          organization_id: string
          requested_fields: string[]
          reviewer_id: string
          unit_id: string
        }
        Insert: {
          created_at?: string
          decision: Database["public"]["Enums"]["onboarding_review_decision"]
          id?: string
          notes: string
          onboarding_id: string
          organization_id: string
          requested_fields?: string[]
          reviewer_id: string
          unit_id: string
        }
        Update: {
          created_at?: string
          decision?: Database["public"]["Enums"]["onboarding_review_decision"]
          id?: string
          notes?: string
          onboarding_id?: string
          organization_id?: string
          requested_fields?: string[]
          reviewer_id?: string
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "onboarding_reviews_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "onboarding_reviews_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "onboarding_reviews_organization_id_unit_id_onboarding_id_fkey"
            columns: ["organization_id", "unit_id", "onboarding_id"]
            isOneToOne: false
            referencedRelation: "onboarding_versions"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      onboarding_versions: {
        Row: {
          document: Json
          id: string
          organization_id: string
          reviewed_at: string | null
          reviewed_by: string | null
          revision: number
          schema_version: number
          status: Database["public"]["Enums"]["onboarding_status"]
          submitted_at: string | null
          unit_id: string
          version: number
        }
        Insert: {
          document?: Json
          id?: string
          organization_id: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          revision?: number
          schema_version: number
          status?: Database["public"]["Enums"]["onboarding_status"]
          submitted_at?: string | null
          unit_id: string
          version: number
        }
        Update: {
          document?: Json
          id?: string
          organization_id?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          revision?: number
          schema_version?: number
          status?: Database["public"]["Enums"]["onboarding_status"]
          submitted_at?: string | null
          unit_id?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "onboarding_versions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "onboarding_versions_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      organization_invitations: {
        Row: {
          accepted_at: string | null
          accepted_by: string | null
          all_units: boolean
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string
          organization_id: string
          revoked_at: string | null
          role: Database["public"]["Enums"]["academy_role"]
          token_hash: string
          unit_id: string | null
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          all_units?: boolean
          created_at?: string
          email: string
          expires_at: string
          id?: string
          invited_by: string
          organization_id: string
          revoked_at?: string | null
          role: Database["public"]["Enums"]["academy_role"]
          token_hash: string
          unit_id?: string | null
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          all_units?: boolean
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string
          organization_id?: string
          revoked_at?: string | null
          role?: Database["public"]["Enums"]["academy_role"]
          token_hash?: string
          unit_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_invitations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_invitations_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      organizations: {
        Row: {
          id: string
          name: string
          plan: string
          status: Database["public"]["Enums"]["organization_status"]
        }
        Insert: {
          id?: string
          name: string
          plan?: string
          status?: Database["public"]["Enums"]["organization_status"]
        }
        Update: {
          id?: string
          name?: string
          plan?: string
          status?: Database["public"]["Enums"]["organization_status"]
        }
        Relationships: []
      }
      privacy_requests: {
        Row: {
          completed_at: string | null
          contact_id: string
          handled_by: string | null
          id: string
          notes: string | null
          organization_id: string
          request_kind: string
          requested_at: string
          status: string
          unit_id: string | null
          verified_at: string | null
        }
        Insert: {
          completed_at?: string | null
          contact_id: string
          handled_by?: string | null
          id?: string
          notes?: string | null
          organization_id: string
          request_kind: string
          requested_at?: string
          status?: string
          unit_id?: string | null
          verified_at?: string | null
        }
        Update: {
          completed_at?: string | null
          contact_id?: string
          handled_by?: string | null
          id?: string
          notes?: string | null
          organization_id?: string
          request_kind?: string
          requested_at?: string
          status?: string
          unit_id?: string | null
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "privacy_requests_organization_id_contact_id_fkey"
            columns: ["organization_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "crm_contacts"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "privacy_requests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "privacy_requests_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      queue_members: {
        Row: {
          active: boolean
          capacity: number
          organization_id: string
          queue_id: string
          unit_id: string
          user_id: string
        }
        Insert: {
          active?: boolean
          capacity?: number
          organization_id: string
          queue_id: string
          unit_id: string
          user_id: string
        }
        Update: {
          active?: boolean
          capacity?: number
          organization_id?: string
          queue_id?: string
          unit_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "queue_members_organization_id_unit_id_fkey"
            columns: ["organization_id", "unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "queue_members_organization_id_unit_id_queue_id_fkey"
            columns: ["organization_id", "unit_id", "queue_id"]
            isOneToOne: false
            referencedRelation: "conversation_queues"
            referencedColumns: ["organization_id", "unit_id", "id"]
          },
        ]
      }
      support_access_grants: {
        Row: {
          expires_at: string
          granted_by: string
          id: string
          mode: Database["public"]["Enums"]["support_mode"]
          organization_id: string
          reason: string
          revoked_at: string | null
          starts_at: string
          user_id: string
        }
        Insert: {
          expires_at: string
          granted_by: string
          id?: string
          mode: Database["public"]["Enums"]["support_mode"]
          organization_id: string
          reason: string
          revoked_at?: string | null
          starts_at?: string
          user_id: string
        }
        Update: {
          expires_at?: string
          granted_by?: string
          id?: string
          mode?: Database["public"]["Enums"]["support_mode"]
          organization_id?: string
          reason?: string
          revoked_at?: string | null
          starts_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "support_access_grants_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      units: {
        Row: {
          id: string
          name: string
          organization_id: string
        }
        Insert: {
          id?: string
          name: string
          organization_id: string
        }
        Update: {
          id?: string
          name?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "units_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_organization_invitation: {
        Args: { p_email: string; p_token_hash: string; p_user_id: string }
        Returns: Json
      }
      anonymize_crm_contact: {
        Args: {
          p_actor_id: string
          p_contact_id: string
          p_organization_id: string
          p_request_id: string
        }
        Returns: boolean
      }
      approve_knowledge_version: {
        Args: {
          p_organization_id: string
          p_source_id: string
          p_unit_id: string
          p_valid_until: string
          p_version_id: string
        }
        Returns: Json
      }
      channel_runtime_secret: {
        Args: { p_connection_id: string }
        Returns: Json
      }
      claim_outbox: {
        Args: { p_lease_seconds: number; p_limit: number; p_worker_id: string }
        Returns: {
          attempts: number
          correlation_id: string
          entity_id: string
          event_type: string
          id: string
          organization_id: string
          payload: Json
          unit_id: string
        }[]
      }
      complete_outbox: {
        Args: { p_id: string; p_worker_id: string }
        Returns: boolean
      }
      configure_evolution_channel: {
        Args: {
          p_actor_id: string
          p_api_key: string
          p_base_url: string
          p_instance: string
          p_name: string
          p_organization_id: string
          p_unit_id: string
          p_webhook_secret: string
          p_webhook_token_hash: string
        }
        Returns: string
      }
      create_crm_opportunity: {
        Args: {
          p_campaign: string
          p_contact_id: string
          p_external_key: string
          p_idempotency_key: string
          p_organization_id: string
          p_pipeline_id: string
          p_source: string
          p_stage_id: string
          p_title: string
          p_unit_id: string
        }
        Returns: Json
      }
      create_organization_invitation: {
        Args: {
          p_actor_id: string
          p_all_units: boolean
          p_email: string
          p_expires_at: string
          p_organization_id: string
          p_role: Database["public"]["Enums"]["academy_role"]
          p_token_hash: string
          p_unit_id: string
        }
        Returns: string
      }
      crm_attribution_summary: {
        Args: { p_organization_id: string; p_unit_id: string }
        Returns: {
          campaign: string
          lost_count: number
          open_count: number
          source: string
          won_count: number
        }[]
      }
      crm_authorize: {
        Args: {
          p_actor_id: string
          p_capability: string
          p_organization_id: string
          p_unit_id: string
        }
        Returns: boolean
      }
      crm_dashboard: {
        Args: { p_organization_id: string; p_unit_id: string }
        Returns: Json
      }
      export_crm_contact: {
        Args: { p_contact_id: string; p_organization_id: string }
        Returns: Json
      }
      ingest_inbound_message: {
        Args: {
          p_body: string
          p_connection_id: string
          p_external_message_id: string
          p_external_thread_id: string
          p_idempotency_key: string
          p_provider_at: string
          p_receipt_id: string
          p_sender_e164: string
          p_sender_name: string
        }
        Returns: Json
      }
      ingest_knowledge_document: {
        Args: {
          p_actor_id: string
          p_chunks: Json
          p_content_sha256: string
          p_organization_id: string
          p_source_id: string
          p_title: string
          p_unit_id: string
        }
        Returns: Json
      }
      move_crm_opportunity: {
        Args: {
          p_expected_stage_id: string
          p_idempotency_key: string
          p_opportunity_id: string
          p_organization_id: string
          p_reason: string
          p_to_stage_id: string
          p_unit_id: string
        }
        Returns: Json
      }
      my_accessible_contexts: {
        Args: never
        Returns: {
          organization_id: string
          organization_name: string
          roles: Database["public"]["Enums"]["academy_role"][]
          unit_id: string
          unit_name: string
        }[]
      }
      my_platform_roles: {
        Args: never
        Returns: Database["public"]["Enums"]["platform_role"][]
      }
      onboarding_review_attachment: {
        Args: { p_actor_id: string; p_attachment_id: string }
        Returns: Json
      }
      onboarding_review_detail: {
        Args: { p_actor_id: string; p_onboarding_id: string }
        Returns: Json
      }
      onboarding_review_queue: { Args: { p_actor_id: string }; Returns: Json }
      provision_organization: {
        Args: {
          p_actor_id: string
          p_name: string
          p_plan?: string
          p_unit_name: string
        }
        Returns: Json
      }
      queue_human_message: {
        Args: {
          p_body: string
          p_conversation_id: string
          p_idempotency_key: string
          p_organization_id: string
          p_reply_to: string
          p_unit_id: string
        }
        Returns: Json
      }
      queue_webhook_event: {
        Args: {
          p_connection_id: string
          p_correlation_id: string
          p_external_event_id: string
          p_payload: Json
          p_payload_sha256: string
          p_provider_at: string
        }
        Returns: boolean
      }
      record_appointment_result: {
        Args: {
          p_appointment_id: string
          p_organization_id: string
          p_reason: string
          p_status: Database["public"]["Enums"]["crm_appointment_status"]
          p_target_stage_id: string
          p_unit_id: string
        }
        Returns: Json
      }
      record_delivery_event: {
        Args: {
          p_error_code: string
          p_message_id: string
          p_provider_at: string
          p_provider_event_id: string
          p_state: Database["public"]["Enums"]["message_delivery_state"]
        }
        Returns: boolean
      }
      retry_outbox: {
        Args: { p_error_code: string; p_id: string; p_worker_id: string }
        Returns: boolean
      }
      return_conversation_to_ai: {
        Args: {
          p_conversation_id: string
          p_organization_id: string
          p_reason: string
          p_unit_id: string
        }
        Returns: Json
      }
      review_onboarding: {
        Args: {
          p_actor_id: string
          p_decision: Database["public"]["Enums"]["onboarding_review_decision"]
          p_notes: string
          p_onboarding_id: string
          p_requested_fields?: string[]
        }
        Returns: string
      }
      revoke_channel: {
        Args: { p_actor_id: string; p_connection_id: string }
        Returns: boolean
      }
      search_authorized_knowledge: {
        Args: {
          p_limit: number
          p_organization_id: string
          p_query: string
          p_unit_id: string
        }
        Returns: {
          content: string
          rank: number
          source_id: string
          version_id: string
        }[]
      }
      takeover_conversation: {
        Args: {
          p_conversation_id: string
          p_idempotency_key: string
          p_organization_id: string
          p_reason: string
          p_unit_id: string
        }
        Returns: Json
      }
      upsert_crm_contact: {
        Args: {
          p_city: string
          p_email: string
          p_external_key: string
          p_idempotency_key: string
          p_name: string
          p_organization_id: string
          p_phone: string
          p_source: string
          p_unit_id: string
        }
        Returns: Json
      }
    }
    Enums: {
      academy_role:
        | "academy_admin"
        | "marketing_operator"
        | "academy_attendant"
        | "viewer"
      ai_run_status:
        | "started"
        | "completed"
        | "blocked"
        | "failed"
        | "transferred"
      channel_connection_status:
        | "unconfigured"
        | "connecting"
        | "active"
        | "paused"
        | "degraded"
        | "revoked"
      conversation_state:
        | "ai_active"
        | "waiting_human"
        | "human_active"
        | "paused"
        | "closed"
      crm_appointment_status:
        | "scheduled"
        | "confirmed"
        | "attended"
        | "no_show"
        | "rescheduled"
        | "cancelled"
        | "enrolled"
        | "lost"
      crm_identifier_kind: "phone" | "email" | "external"
      crm_opportunity_status: "open" | "won" | "lost"
      crm_task_priority: "low" | "normal" | "high" | "urgent"
      crm_task_status: "open" | "done" | "cancelled"
      indexing_status: "pending" | "processing" | "ready" | "failed"
      knowledge_status: "draft" | "approved" | "expired" | "revoked"
      message_author_kind: "contact" | "human" | "ai" | "system"
      message_delivery_state:
        | "pending"
        | "accepted"
        | "sent"
        | "delivered"
        | "read"
        | "failed"
      message_direction: "inbound" | "outbound"
      messaging_provider: "whatsapp" | "instagram" | "tiktok"
      onboarding_field_type:
        | "short_text"
        | "long_text"
        | "number"
        | "currency"
        | "boolean"
        | "single_select"
        | "multi_select"
        | "date"
        | "url"
        | "email"
        | "phone"
      onboarding_review_decision: "approved" | "changes_requested"
      onboarding_scope: "organization" | "unit"
      onboarding_status: "draft" | "submitted" | "approved" | "rejected"
      organization_status: "active" | "suspended"
      platform_role: "supreme" | "support"
      support_mode: "read_only" | "read_write"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      academy_role: [
        "academy_admin",
        "marketing_operator",
        "academy_attendant",
        "viewer",
      ],
      ai_run_status: [
        "started",
        "completed",
        "blocked",
        "failed",
        "transferred",
      ],
      channel_connection_status: [
        "unconfigured",
        "connecting",
        "active",
        "paused",
        "degraded",
        "revoked",
      ],
      conversation_state: [
        "ai_active",
        "waiting_human",
        "human_active",
        "paused",
        "closed",
      ],
      crm_appointment_status: [
        "scheduled",
        "confirmed",
        "attended",
        "no_show",
        "rescheduled",
        "cancelled",
        "enrolled",
        "lost",
      ],
      crm_identifier_kind: ["phone", "email", "external"],
      crm_opportunity_status: ["open", "won", "lost"],
      crm_task_priority: ["low", "normal", "high", "urgent"],
      crm_task_status: ["open", "done", "cancelled"],
      indexing_status: ["pending", "processing", "ready", "failed"],
      knowledge_status: ["draft", "approved", "expired", "revoked"],
      message_author_kind: ["contact", "human", "ai", "system"],
      message_delivery_state: [
        "pending",
        "accepted",
        "sent",
        "delivered",
        "read",
        "failed",
      ],
      message_direction: ["inbound", "outbound"],
      messaging_provider: ["whatsapp", "instagram", "tiktok"],
      onboarding_field_type: [
        "short_text",
        "long_text",
        "number",
        "currency",
        "boolean",
        "single_select",
        "multi_select",
        "date",
        "url",
        "email",
        "phone",
      ],
      onboarding_review_decision: ["approved", "changes_requested"],
      onboarding_scope: ["organization", "unit"],
      onboarding_status: ["draft", "submitted", "approved", "rejected"],
      organization_status: ["active", "suspended"],
      platform_role: ["supreme", "support"],
      support_mode: ["read_only", "read_write"],
    },
  },
} as const
