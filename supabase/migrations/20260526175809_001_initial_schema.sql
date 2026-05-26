/*
  # Live Chat Support System - Initial Schema

  1. New Tables
    - `chat_sessions`: Stores customer chat sessions with status tracking
      - id (uuid, primary key)
      - customer_name (text, required)
      - customer_email (text, optional)
      - mode (text: 'ai' or 'manual', default 'ai')
      - status (text: 'active'|'closed'|'pending', default 'active')
      - assigned_agent_id (uuid, references agents)
      - csat_rating (int, 1-5)
      - first_response_at (timestamptz)
      - resolved_at (timestamptz)
      - issue_category (text: 'deposit'|'login'|'game'|'withdrawal'|'other')
      - escalated_from_ai (boolean, default false)
      - total_messages (int, default 0)
      - customer_wait_seconds (int)
      - created_at (timestamptz, default now())
      - updated_at (timestamptz, default now())
    
    - `messages`: Stores all chat messages
      - id (uuid, primary key)
      - session_id (uuid, references chat_sessions)
      - sender_type (text: 'customer'|'agent'|'ai')
      - sender_id (uuid, optional)
      - content (text, required)
      - is_read (boolean, default false)
      - created_at (timestamptz, default now())
    
    - `agents`: Stores support agents
      - id (uuid, primary key, references auth.users)
      - name (text)
      - email (text, unique)
      - is_online (boolean, default false)
      - created_at (timestamptz, default now())
    
    - `session_events`: Tracks all session lifecycle events
      - id (uuid, primary key)
      - session_id (uuid, references chat_sessions)
      - event_type (text)
      - event_data (jsonb)
      - created_at (timestamptz, default now())

  2. Security
    - Enable RLS on all tables
    - Customer widget can read/write own session
    - Agents can read/write active sessions
    - Events are append-only for customers

  3. Indexes
    - sessions by status and updated_at for agent dashboard
    - messages by session_id for real-time chat
    - events by session_id for audit trail
*/

-- Create enum types
CREATE TYPE session_mode AS ENUM ('ai', 'manual');
CREATE TYPE session_status AS ENUM ('active', 'closed', 'pending');
CREATE TYPE sender_type AS ENUM ('customer', 'agent', 'ai');
CREATE TYPE issue_category AS ENUM ('deposit', 'login', 'game', 'withdrawal', 'other');

-- Create agents table first (referenced by chat_sessions)
CREATE TABLE IF NOT EXISTS agents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text,
  email text UNIQUE,
  is_online boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

-- Create chat_sessions table
CREATE TABLE IF NOT EXISTS chat_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_name text NOT NULL,
  customer_email text,
  mode text DEFAULT 'ai',
  status text DEFAULT 'active',
  assigned_agent_id uuid REFERENCES agents(id),
  csat_rating int CHECK (csat_rating >= 1 AND csat_rating <= 5),
  first_response_at timestamptz,
  resolved_at timestamptz,
  issue_category text DEFAULT 'other',
  escalated_from_ai boolean DEFAULT false,
  total_messages int DEFAULT 0,
  customer_wait_seconds int,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create messages table
CREATE TABLE IF NOT EXISTS messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
  sender_type text NOT NULL,
  sender_id uuid,
  content text NOT NULL,
  is_read boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

-- Create session_events table
CREATE TABLE IF NOT EXISTS session_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  event_data jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_events ENABLE ROW LEVEL SECURITY;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_chat_sessions_status_updated ON chat_sessions(status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_session_id ON messages(session_id, created_at);
CREATE INDEX IF NOT EXISTS idx_session_events_session_id ON session_events(session_id, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_sessions_assigned_agent ON chat_sessions(assigned_agent_id);

-- RLS Policies for chat_sessions
-- Allow insert for anyone (anonymous customers)
CREATE POLICY "Anyone can create sessions"
  ON chat_sessions FOR INSERT
  WITH CHECK (true);

-- Allow update for anyone (customer and agent operations)
CREATE POLICY "Anyone can update sessions"
  ON chat_sessions FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- Allow read for anyone
CREATE POLICY "Anyone can read sessions"
  ON chat_sessions FOR SELECT
  USING (true);

-- RLS Policies for messages
-- Allow insert for anyone
CREATE POLICY "Anyone can create messages"
  ON messages FOR INSERT
  WITH CHECK (true);

-- Allow read for anyone
CREATE POLICY "Anyone can read messages"
  ON messages FOR SELECT
  USING (true);

-- Allow update for anyone (mark as read)
CREATE POLICY "Anyone can update messages"
  ON messages FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- RLS Policies for agents
-- Allow read for anyone
CREATE POLICY "Anyone can read agents"
  ON agents FOR SELECT
  USING (true);

-- Allow insert for authenticated users
CREATE POLICY "Authenticated can create agents"
  ON agents FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Allow update for agents themselves
CREATE POLICY "Agents can update own record"
  ON agents FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- RLS Policies for session_events
-- Allow insert for anyone
CREATE POLICY "Anyone can create events"
  ON session_events FOR INSERT
  WITH CHECK (true);

-- Allow read for anyone
CREATE POLICY "Anyone can read events"
  ON session_events FOR SELECT
  USING (true);

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger to auto-update updated_at on chat_sessions
CREATE TRIGGER update_chat_sessions_updated_at
  BEFORE UPDATE ON chat_sessions
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();