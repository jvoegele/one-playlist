export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never;
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      graphql: {
        Args: {
          extensions?: Json;
          operationName?: string;
          query?: string;
          variables?: Json;
        };
        Returns: Json;
      };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  public: {
    Tables: {
      library_playlist_items: {
        Row: {
          album: string | null;
          artists: string[];
          created_at: string;
          duration_seconds: number | null;
          id: string;
          isrc: string | null;
          playlist_id: string;
          position: number;
          recording_id: string | null;
          title: string;
          updated_at: string;
          user_id: string;
          version: string | null;
        };
        Insert: {
          album?: string | null;
          artists?: string[];
          created_at?: string;
          duration_seconds?: number | null;
          id?: string;
          isrc?: string | null;
          playlist_id: string;
          position: number;
          recording_id?: string | null;
          title: string;
          updated_at?: string;
          user_id: string;
          version?: string | null;
        };
        Update: {
          album?: string | null;
          artists?: string[];
          created_at?: string;
          duration_seconds?: number | null;
          id?: string;
          isrc?: string | null;
          playlist_id?: string;
          position?: number;
          recording_id?: string | null;
          title?: string;
          updated_at?: string;
          user_id?: string;
          version?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "library_playlist_items_playlist_id_fkey";
            columns: ["playlist_id"];
            isOneToOne: false;
            referencedRelation: "library_playlists";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "library_playlist_items_recording_id_fkey";
            columns: ["recording_id"];
            isOneToOne: false;
            referencedRelation: "library_recordings";
            referencedColumns: ["id"];
          },
        ];
      };
      library_playlists: {
        Row: {
          created_at: string;
          description: string | null;
          id: string;
          name: string;
          updated_at: string;
          user_id: string;
        };
        Insert: {
          created_at?: string;
          description?: string | null;
          id?: string;
          name: string;
          updated_at?: string;
          user_id: string;
        };
        Update: {
          created_at?: string;
          description?: string | null;
          id?: string;
          name?: string;
          updated_at?: string;
          user_id?: string;
        };
        Relationships: [];
      };
      library_recordings: {
        Row: {
          album: string | null;
          album_upc: string | null;
          artists: string[];
          artwork_url: string | null;
          created_at: string;
          duration_seconds: number | null;
          explicit: boolean | null;
          id: string;
          isrc: string | null;
          isrc_disputed: boolean;
          origin_provider: string | null;
          origin_provider_id: string | null;
          title: string;
          track_number: number | null;
          updated_at: string;
          version: string | null;
          volume_number: number | null;
        };
        Insert: {
          album?: string | null;
          album_upc?: string | null;
          artists?: string[];
          artwork_url?: string | null;
          created_at?: string;
          duration_seconds?: number | null;
          explicit?: boolean | null;
          id?: string;
          isrc?: string | null;
          isrc_disputed?: boolean;
          origin_provider?: string | null;
          origin_provider_id?: string | null;
          title: string;
          track_number?: number | null;
          updated_at?: string;
          version?: string | null;
          volume_number?: number | null;
        };
        Update: {
          album?: string | null;
          album_upc?: string | null;
          artists?: string[];
          artwork_url?: string | null;
          created_at?: string;
          duration_seconds?: number | null;
          explicit?: boolean | null;
          id?: string;
          isrc?: string | null;
          isrc_disputed?: boolean;
          origin_provider?: string | null;
          origin_provider_id?: string | null;
          title?: string;
          track_number?: number | null;
          updated_at?: string;
          version?: string | null;
          volume_number?: number | null;
        };
        Relationships: [];
      };
      provider_connections: {
        Row: {
          access_token_expires_at: string | null;
          access_token_secret_id: string | null;
          consecutive_failures: number;
          created_at: string;
          display_name: string | null;
          id: string;
          last_error: string | null;
          last_refreshed_at: string | null;
          provider: string;
          provider_user_id: string;
          refresh_token_secret_id: string | null;
          scopes: string[];
          server_url: string | null;
          source: string;
          status: string;
          updated_at: string;
          user_id: string;
        };
        Insert: {
          access_token_expires_at?: string | null;
          access_token_secret_id?: string | null;
          consecutive_failures?: number;
          created_at?: string;
          display_name?: string | null;
          id?: string;
          last_error?: string | null;
          last_refreshed_at?: string | null;
          provider: string;
          provider_user_id: string;
          refresh_token_secret_id?: string | null;
          scopes?: string[];
          server_url?: string | null;
          source: string;
          status?: string;
          updated_at?: string;
          user_id: string;
        };
        Update: {
          access_token_expires_at?: string | null;
          access_token_secret_id?: string | null;
          consecutive_failures?: number;
          created_at?: string;
          display_name?: string | null;
          id?: string;
          last_error?: string | null;
          last_refreshed_at?: string | null;
          provider?: string;
          provider_user_id?: string;
          refresh_token_secret_id?: string | null;
          scopes?: string[];
          server_url?: string | null;
          source?: string;
          status?: string;
          updated_at?: string;
          user_id?: string;
        };
        Relationships: [];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      place_entry: {
        Args: { p_after_entry_id: string; p_entry_id: string };
        Returns: undefined;
      };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema = DatabaseWithoutInternals[Extract<
  keyof Database,
  "public"
>];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const;
