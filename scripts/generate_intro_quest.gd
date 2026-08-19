extends SceneTree

## One-time generator: builds the "First Symbiosis" quest graph and saves it
## as a QuestGraphResource .tres at res://quests/intro_quest.tres.
## Run with:
##   Godot --headless --script res://scripts/generate_intro_quest.gd

const QUEST_PATH := "res://quests/intro_quest.tres"

const START_NODE_PATH := "res://addons/quest_weaver/nodes/common/start_node/start_node_resource.gd"
const END_NODE_PATH := "res://addons/quest_weaver/nodes/common/end_node/end_node_resource.gd"
const CTX_NODE_PATH := "res://addons/quest_weaver/nodes/logic/quest_context_node/quest_context_node_resource.gd"
const TASK_NODE_PATH := "res://addons/quest_weaver/nodes/action/task_node/task_node_resource.gd"
const QUEST_NODE_PATH := "res://addons/quest_weaver/nodes/logic/quest_node/quest_node_resource.gd"
const OBJECTIVE_PATH := "res://addons/quest_weaver/editor/conditions/objective_resource.gd"
const GRAPH_PATH := "res://addons/quest_weaver/core/quest_graph_resource.gd"


func _init() -> void:
	process_frame.connect(_run)


func _run() -> void:
	print("=== Generating First Symbiosis quest graph ===")

	var StartNodeScript: Script = load(START_NODE_PATH)
	var EndNodeScript: Script = load(END_NODE_PATH)
	var CtxNodeScript: Script = load(CTX_NODE_PATH)
	var TaskNodeScript: Script = load(TASK_NODE_PATH)
	var QuestNodeScript: Script = load(QUEST_NODE_PATH)
	var ObjectiveScript: Script = load(OBJECTIVE_PATH)
	var GraphScript: Script = load(GRAPH_PATH)

	var graph = GraphScript.new()

	# --- Nodes ---
	var start_node = StartNodeScript.new()
	start_node.id = &"start"
	start_node.graph_position = Vector2(0, 0)
	graph.add_node(start_node)

	var ctx_node = CtxNodeScript.new()
	ctx_node.id = &"ctx"
	ctx_node.quest_id = &"first_symbiosis"
	ctx_node.quest_type = 0  # QuestType.MAIN
	ctx_node.quest_title = "First Symbiosis"
	ctx_node.quest_description = "Approach the drifting Void-Fauna Leviathan, undergo the Covenant of Symbiosis ritual, and bond with the organism to become its pilot. Then take flight for the first time."
	ctx_node.log_on_start = "A bioluminescent pulse ripples across the void — the Leviathan awaits. Approach with caution."
	ctx_node.graph_position = Vector2(250, 0)
	graph.add_node(ctx_node)

	# Objective 1: Approach the Void-Fauna
	var task_approach = TaskNodeScript.new()
	task_approach.id = &"task_approach"
	task_approach.objectives.clear()
	var obj_approach = ObjectiveScript.new()
	obj_approach.id = &"obj_approach_void_fauna"
	obj_approach.description = "Approach the Void-Fauna"
	obj_approach.trigger_type = 0  # TriggerType.MANUAL
	task_approach.objectives.append(obj_approach)
	task_approach.graph_position = Vector2(500, 0)
	graph.add_node(task_approach)

	# Objective 2: Complete the Covenant dialogue
	var task_dialogue = TaskNodeScript.new()
	task_dialogue.id = &"task_dialogue"
	task_dialogue.objectives.clear()
	var obj_dialogue = ObjectiveScript.new()
	obj_dialogue.id = &"obj_complete_covenant_dialogue"
	obj_dialogue.description = "Complete the Covenant dialogue"
	obj_dialogue.trigger_type = 0  # TriggerType.MANUAL
	task_dialogue.objectives.append(obj_dialogue)
	task_dialogue.graph_position = Vector2(750, 0)
	graph.add_node(task_dialogue)

	# Objective 3: Bond with the Void-Fauna
	var task_bond = TaskNodeScript.new()
	task_bond.id = &"task_bond"
	task_bond.objectives.clear()
	var obj_bond = ObjectiveScript.new()
	obj_bond.id = &"obj_bond_with_void_fauna"
	obj_bond.description = "Bond with the Void-Fauna (becomes your ship)"
	obj_bond.trigger_type = 0  # TriggerType.MANUAL
	task_bond.objectives.append(obj_bond)
	task_bond.graph_position = Vector2(1000, 0)
	graph.add_node(task_bond)

	# Objective 4: Take flight for the first time
	var task_flight = TaskNodeScript.new()
	task_flight.id = &"task_flight"
	task_flight.objectives.clear()
	var obj_flight = ObjectiveScript.new()
	obj_flight.id = &"obj_take_first_flight"
	obj_flight.description = "Take flight for the first time"
	obj_flight.trigger_type = 0  # TriggerType.MANUAL
	task_flight.objectives.append(obj_flight)
	task_flight.graph_position = Vector2(1250, 0)
	graph.add_node(task_flight)

	# Quest completion node: marks "first_symbiosis" as COMPLETED
	var quest_complete_node = QuestNodeScript.new()
	quest_complete_node.id = &"quest_complete"
	quest_complete_node.target_quest_id = &"first_symbiosis"
	quest_complete_node.action = 0  # QuestAction.COMPLETE
	quest_complete_node.graph_position = Vector2(1500, 0)
	graph.add_node(quest_complete_node)

	var end_node = EndNodeScript.new()
	end_node.id = &"end"
	end_node.graph_position = Vector2(1750, 0)
	graph.add_node(end_node)

	# --- Connections (from_node, from_port, to_node, to_port) ---
	graph.connections.append({"from_node": &"start", "from_port": 0, "to_node": &"ctx", "to_port": 0})
	graph.connections.append({"from_node": &"ctx", "from_port": 0, "to_node": &"task_approach", "to_port": 0})
	graph.connections.append({"from_node": &"task_approach", "from_port": 0, "to_node": &"task_dialogue", "to_port": 0})
	graph.connections.append({"from_node": &"task_dialogue", "from_port": 0, "to_node": &"task_bond", "to_port": 0})
	graph.connections.append({"from_node": &"task_bond", "from_port": 0, "to_node": &"task_flight", "to_port": 0})
	graph.connections.append({"from_node": &"task_flight", "from_port": 0, "to_node": &"quest_complete", "to_port": 0})
	graph.connections.append({"from_node": &"quest_complete", "from_port": 0, "to_node": &"end", "to_port": 0})

	# --- Save ---
	graph.resource_path = QUEST_PATH
	var err = ResourceSaver.save(graph, QUEST_PATH)
	if err != OK:
		push_error("generate_intro_quest: Failed to save quest graph (error %d)." % err)
		quit(1)
		return

	print("  ✓ Saved quest graph to %s" % QUEST_PATH)
	print("  ✓ Nodes: %d, Connections: %d" % [graph.nodes.size(), graph.connections.size()])
	print("  ✓ Quest ID: first_symbiosis")
	print("  ✓ Objectives: approach, dialogue, bond, flight")
	print("=== Done ===")
	quit()
