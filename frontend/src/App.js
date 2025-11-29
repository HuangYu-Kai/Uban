import React, { useState, useCallback, useMemo } from 'react';
import ReactFlow, {
  MiniMap,
  Controls,
  Background,
  useEdgesState,
  addEdge,
  applyNodeChanges,
} from 'reactflow';

import CustomNode from './CustomNode';
import 'reactflow/dist/style.css';
import './CustomNode.css';
import './App.css';

const nodeTypes = { custom: CustomNode };
const flowKey = 'flow-key';

let nodeIdCounter = 1;

function App() {
  const [nodes, setNodes] = useState([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([]);

  const onNodesChange = useCallback(
    (changes) => setNodes((nds) => applyNodeChanges(changes, nds)),
    [setNodes]
  );

  const onConnect = useCallback(
    (params) => setEdges((eds) => addEdge(params, eds)),
    [setEdges]
  );

  const handleDataChange = useCallback((nodeId, newData) => {
    setNodes((nds) =>
      nds.map((node) => {
        if (node.id === nodeId) {
          return { ...node, data: { ...node.data, ...newData } };
        }
        return node;
      })
    );
  }, [setNodes]);

  const handleDelete = useCallback((nodeIdToDelete) => {
    setNodes((nds) => nds.filter((node) => node.id !== nodeIdToDelete));
    setEdges((eds) => eds.filter((edge) => edge.source !== nodeIdToDelete && edge.target !== nodeIdToDelete));
  }, [setNodes, setEdges]);

  const nodesWithHandlers = useMemo(() => {
    return nodes.map((node) => ({
      ...node,
      data: {
        ...node.data,
        onDataChange: (data) => handleDataChange(node.id, data),
        onDelete: () => handleDelete(node.id),
      },
    }));
  }, [nodes, handleDataChange, handleDelete]);

  const addNode = useCallback(() => {
    const id = nodeIdCounter++;
    const newNode = {
      id: `node-${id}`,
      type: 'custom',
      position: {
        x: Math.random() * 400,
        y: Math.random() * 400,
      },
      data: {
        name: `Node ${id}`,
        color: '#ffffff',
      },
    };
    setNodes((nds) => nds.concat(newNode));
  }, []);

  const onSave = useCallback(() => {
    const flow = {
      nodes: nodes,
      edges: edges,
      nodeIdCounter: nodeIdCounter
    };
    localStorage.setItem(flowKey, JSON.stringify(flow));
    alert('Flow saved!');
  }, [nodes, edges]);

  const onRestore = useCallback(() => {
    const restore = () => {
      const flow = JSON.parse(localStorage.getItem(flowKey));

      if (flow) {
        setNodes(flow.nodes || []);
        setEdges(flow.edges || []);
        nodeIdCounter = flow.nodeIdCounter || 1;
      }
    };

    restore();
  }, [setNodes, setEdges]);

  return (
    <div className="App">
      <div className="controls">
        <button onClick={addNode}>Add Node</button>
        <button onClick={onSave}>Save</button>
        <button onClick={onRestore}>Restore</button>
      </div>
      <ReactFlow
        nodes={nodesWithHandlers}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={onConnect}
        nodeTypes={nodeTypes}
        fitView
      >
        <MiniMap />
        <Controls />
        <Background />
      </ReactFlow>
    </div>
  );
}

export default App;
