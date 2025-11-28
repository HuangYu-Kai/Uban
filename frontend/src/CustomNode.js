import React, { memo, useState } from 'react';
import { Handle, Position } from 'reactflow';
import './CustomNode.css';

export default memo(({ data, id }) => {
  const [isCollapsed, setIsCollapsed] = useState(false);

  const onNameChange = (evt) => {
    data.onDataChange({ ...data, name: evt.target.value });
  };

  const onColorChange = (evt) => {
    data.onDataChange({ ...data, color: evt.target.value });
  };

  const onDelete = () => {
    data.onDelete(id);
  }

  const toggleCollapse = () => {
    setIsCollapsed(!isCollapsed);
  }

  return (
    <div className="custom-node" style={{ backgroundColor: data.color || 'white' }}>
      <div className="node-header">
        <span className="node-title">{data.name || 'Custom Node'}</span>
        <button onClick={toggleCollapse} className="collapse-button">
          {isCollapsed ? '+' : '-'}
        </button>
        <button onClick={onDelete} className="delete-button">×</button>
      </div>
      {!isCollapsed && (
        <div className="node-body">
          <label>Name:</label>
          <input
            type="text"
            value={data.name || ''}
            onChange={onNameChange}
          />
          <label>Background Color:</label>
          <input
            type="color"
            value={data.color || '#ffffff'}
            onChange={onColorChange}
          />
        </div>
      )}
      <Handle type="target" position={Position.Left} id="a" />
      <Handle type="source" position={Position.Right} id="b" />
    </div>
  );
});
