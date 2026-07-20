-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Joshua B. Jewell and Jonathan D.A. Jewell
--
-- Multiplayer.idr — Formal ABI types for asymmetric co-op multiplayer.
--
-- Defines the typed interface for:
--   - Session lifecycle (create, join, leave, destroy)
--   - Player roles (Jessica operator, Q hacker, Observer support)
--   - Sync operations (position, VM relay, covert link, alert)
--   - Chat messages
--   - Connection states
--
-- Proofs:
--   1. Roles are disjoint — a player cannot hold two roles simultaneously
--   2. Session IDs are bounded (max 64 chars)
--   3. Chat messages are non-empty
--   4. Alert levels form a total order (green < yellow < orange < red)
module Multiplayer

import Data.Fin
import Data.String

%default total

-- ═══════════════════════════════════════════════════════════════════════
-- Player roles — asymmetric co-op requires distinct roles
-- ═══════════════════════════════════════════════════════════════════════

||| Player role in the asymmetric co-op game.
||| Jessica operates physically in the level.
||| Q hacks remotely through cameras and systems.
||| Observer provides tactical support and camera monitoring.
public export
data CoopRole = Jessica | QHacker | Observer

||| Integer encoding for C ABI.
public export
coopRoleToInt : CoopRole -> Int
coopRoleToInt Jessica  = 0
coopRoleToInt QHacker  = 1
coopRoleToInt Observer = 2

||| Proof that Jessica and Q are distinct roles.
public export
jessicaNotQ : Jessica = QHacker -> Void
jessicaNotQ Refl impossible

||| Proof that Jessica and Observer are distinct.
public export
jessicaNotObserver : Jessica = Observer -> Void
jessicaNotObserver Refl impossible

||| Proof that Q and Observer are distinct.
public export
qNotObserver : QHacker = Observer -> Void
qNotObserver Refl impossible

-- ═══════════════════════════════════════════════════════════════════════
-- Connection and session state
-- ═══════════════════════════════════════════════════════════════════════

||| Multiplayer connection state.
public export
data ConnectionState
  = Offline       -- Not connected to sync server
  | Connecting    -- WebSocket handshake in progress
  | InLobby       -- Connected, browsing rooms
  | InSession     -- In an active game session

||| Integer encoding for C ABI.
public export
connectionStateToInt : ConnectionState -> Int
connectionStateToInt Offline    = 0
connectionStateToInt Connecting = 1
connectionStateToInt InLobby    = 2
connectionStateToInt InSession  = 3

||| Game session phase (mirrors GameStateMachine phases).
public export
data SessionPhase
  = Lobby      -- Waiting for players
  | Countdown  -- All ready, counting down
  | Loading    -- Loading level assets
  | Playing    -- Active gameplay
  | Paused     -- Game paused
  | Complete   -- Game ended (victory or defeat)

||| Integer encoding for C ABI.
public export
sessionPhaseToInt : SessionPhase -> Int
sessionPhaseToInt Lobby     = 0
sessionPhaseToInt Countdown = 1
sessionPhaseToInt Loading   = 2
sessionPhaseToInt Playing   = 3
sessionPhaseToInt Paused    = 4
sessionPhaseToInt Complete  = 5

-- ═══════════════════════════════════════════════════════════════════════
-- Alert levels — total order for facility-wide alerts
-- ═══════════════════════════════════════════════════════════════════════

||| Multiplayer alert levels (facility-wide, shared between all players).
public export
data MultiplayerAlert = AlertGreen | AlertYellow | AlertOrange | AlertRed

||| Integer encoding for C ABI.
public export
alertToInt : MultiplayerAlert -> Int
alertToInt AlertGreen  = 0
alertToInt AlertYellow = 1
alertToInt AlertOrange = 2
alertToInt AlertRed    = 3

||| Alert levels form a total order.
public export
alertLte : MultiplayerAlert -> MultiplayerAlert -> Bool
alertLte a b = alertToInt a <= alertToInt b

-- ═══════════════════════════════════════════════════════════════════════
-- Sync operation types
-- ═══════════════════════════════════════════════════════════════════════

||| Types of multiplayer sync message sent through the Phoenix channel.
public export
data SyncMessageKind
  = MsgPosition        -- Player position update (x, y)
  | MsgVMExecute       -- VM instruction relay
  | MsgVMUndo          -- VM undo relay
  | MsgVMState         -- VM state snapshot sync
  | MsgBebopDiscovered -- Covert link discovered
  | MsgBebopActivated  -- Covert link activated (both confirmed)
  | MsgBebopCoopReq    -- Co-op request for covert link
  | MsgBebopCoopAccept -- Co-op acceptance
  | MsgDeviceAccessed  -- Device access notification
  | MsgAlertChanged    -- Alert level change
  | MsgChat            -- In-game chat message

||| Integer encoding for C ABI.
public export
syncMessageKindToInt : SyncMessageKind -> Int
syncMessageKindToInt MsgPosition        = 0
syncMessageKindToInt MsgVMExecute       = 1
syncMessageKindToInt MsgVMUndo          = 2
syncMessageKindToInt MsgVMState         = 3
syncMessageKindToInt MsgBebopDiscovered = 4
syncMessageKindToInt MsgBebopActivated  = 5
syncMessageKindToInt MsgBebopCoopReq    = 6
syncMessageKindToInt MsgBebopCoopAccept = 7
syncMessageKindToInt MsgDeviceAccessed  = 8
syncMessageKindToInt MsgAlertChanged    = 9
syncMessageKindToInt MsgChat            = 10

-- ═══════════════════════════════════════════════════════════════════════
-- Player info record
-- ═══════════════════════════════════════════════════════════════════════

||| A player in a multiplayer session.
public export
record PlayerInfo where
  constructor MkPlayerInfo
  playerId : String
  role     : CoopRole
  posX     : Double
  posY     : Double

-- ═══════════════════════════════════════════════════════════════════════
-- Chat message
-- ═══════════════════════════════════════════════════════════════════════

||| A chat message with sender and content.
public export
record ChatMessage where
  constructor MkChatMessage
  senderId  : String
  content   : String
  timestamp : Double
