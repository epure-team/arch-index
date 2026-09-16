module String_set = Set.Make (String)

type reason = Callback_param | Dropped_node

module Reason_set = Set.Make (struct
  type t = reason
  let compare = Stdlib.compare
end)

type residual = {target : string; consumed : int}

module Residual_set = Set.Make (struct
  type t = residual
  let compare = Stdlib.compare
end)

type value = {
  targets : String_set.t;
  reasons : Reason_set.t;
  residuals : Residual_set.t;
}
type cell = int

type t = {
  mutable next : int;
  values : (cell, value) Hashtbl.t;
  outgoing : (cell, cell list) Hashtbl.t;
  watchers : (cell, (t -> string -> unit) list) Hashtbl.t;
  reason_watchers : (cell, (t -> reason -> unit) list) Hashtbl.t;
  residual_watchers : (cell, (t -> residual -> unit) list) Hashtbl.t;
  notifications : notification Queue.t;
  queue : cell Queue.t;
  queued : (cell, unit) Hashtbl.t;
}

and notification =
  | Target_notification of (t -> string -> unit) * string
  | Reason_notification of (t -> reason -> unit) * reason
  | Residual_notification of (t -> residual -> unit) * residual

let bottom = {
  targets = String_set.empty;
  reasons = Reason_set.empty;
  residuals = Residual_set.empty;
}

let create () =
  {
    next = 0;
    values = Hashtbl.create 32;
    outgoing = Hashtbl.create 32;
    watchers = Hashtbl.create 32;
    reason_watchers = Hashtbl.create 32;
    residual_watchers = Hashtbl.create 32;
    notifications = Queue.create ();
    queue = Queue.create ();
    queued = Hashtbl.create 32;
  }

let clone t =
  {
    next = t.next;
    values = Hashtbl.copy t.values;
    outgoing = Hashtbl.copy t.outgoing;
    watchers = Hashtbl.copy t.watchers;
    reason_watchers = Hashtbl.copy t.reason_watchers;
    residual_watchers = Hashtbl.copy t.residual_watchers;
    notifications = Queue.copy t.notifications;
    queue = Queue.copy t.queue;
    queued = Hashtbl.copy t.queued;
  }

let fresh t =
  let cell = t.next in
  t.next <- cell + 1 ;
  Hashtbl.add t.values cell bottom ;
  cell

let enqueue t cell =
  if not (Hashtbl.mem t.queued cell) then (
    Hashtbl.add t.queued cell () ;
    Queue.add cell t.queue)

let update t cell value =
  let previous = Hashtbl.find t.values cell in
  if
    not
      (String_set.equal previous.targets value.targets
      && Reason_set.equal previous.reasons value.reasons
      && Residual_set.equal previous.residuals value.residuals)
  then (
    Hashtbl.replace t.values cell value ;
    enqueue t cell ;
    String_set.iter
      (fun target ->
        if not (String_set.mem target previous.targets) then
          List.iter
            (fun watcher -> Queue.add (Target_notification (watcher, target)) t.notifications)
            (Option.value (Hashtbl.find_opt t.watchers cell) ~default:[]))
      value.targets ;
    Reason_set.iter
      (fun reason ->
        if not (Reason_set.mem reason previous.reasons) then
          List.iter
            (fun watcher -> Queue.add (Reason_notification (watcher, reason)) t.notifications)
            (Option.value (Hashtbl.find_opt t.reason_watchers cell) ~default:[]))
      value.reasons ;
    Residual_set.iter
      (fun residual ->
        if not (Residual_set.mem residual previous.residuals) then
          List.iter
            (fun watcher ->
              Queue.add (Residual_notification (watcher, residual)) t.notifications)
            (Option.value (Hashtbl.find_opt t.residual_watchers cell) ~default:[]))
      value.residuals)

let seed_target t cell target =
  let value = Hashtbl.find t.values cell in
  update t cell {value with targets = String_set.add target value.targets}

let seed_reason t cell reason =
  let value = Hashtbl.find t.values cell in
  update t cell {value with reasons = Reason_set.add reason value.reasons}

let seed_residual t cell residual =
  let value = Hashtbl.find t.values cell in
  update t cell {value with residuals = Residual_set.add residual value.residuals}

let copy t ~src ~dst =
  let successors = Option.value (Hashtbl.find_opt t.outgoing src) ~default:[] in
  if not (List.mem dst successors) then Hashtbl.replace t.outgoing src (dst :: successors) ;
  enqueue t src

let on_target t cell watcher =
  let existing = Option.value (Hashtbl.find_opt t.watchers cell) ~default:[] in
  Hashtbl.replace t.watchers cell (watcher :: existing) ;
  String_set.iter
    (fun target -> Queue.add (Target_notification (watcher, target)) t.notifications)
    (Hashtbl.find t.values cell).targets

let on_reason t cell watcher =
  let existing = Option.value (Hashtbl.find_opt t.reason_watchers cell) ~default:[] in
  Hashtbl.replace t.reason_watchers cell (watcher :: existing) ;
  Reason_set.iter
    (fun reason -> Queue.add (Reason_notification (watcher, reason)) t.notifications)
    (Hashtbl.find t.values cell).reasons

let on_residual t cell watcher =
  let existing = Option.value (Hashtbl.find_opt t.residual_watchers cell) ~default:[] in
  Hashtbl.replace t.residual_watchers cell (watcher :: existing) ;
  Residual_set.iter
    (fun residual ->
      Queue.add (Residual_notification (watcher, residual)) t.notifications)
    (Hashtbl.find t.values cell).residuals

let join left right =
  {
    targets = String_set.union left.targets right.targets;
    reasons = Reason_set.union left.reasons right.reasons;
    residuals = Residual_set.union left.residuals right.residuals;
  }

let solve t =
  while not (Queue.is_empty t.notifications && Queue.is_empty t.queue) do
    if not (Queue.is_empty t.notifications) then
      match Queue.take t.notifications with
      | Target_notification (watcher, target) -> watcher t target
      | Reason_notification (watcher, reason) -> watcher t reason
      | Residual_notification (watcher, residual) -> watcher t residual
    else
      let src = Queue.take t.queue in
      Hashtbl.remove t.queued src ;
      let source = Hashtbl.find t.values src in
      List.iter
        (fun dst -> update t dst (join (Hashtbl.find t.values dst) source))
        (Option.value (Hashtbl.find_opt t.outgoing src) ~default:[])
  done

let value t cell = Hashtbl.find t.values cell
