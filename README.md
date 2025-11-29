
# UniFlow

UniFlow is a lightweight, visual workflow automation platform designed specifically for university students. It allows users to connect popular services like Line, Discord, and Google Sheets through a drag-and-drop interface, enabling them to automate repetitive campus tasks without writing complex code.

Inspired by industrial iPaaS solutions like n8n, UniFlow simplifies the concept of workflow automation for the academic environment. Whether it's notifying a student club via Discord when a Google Form is submitted, or sending daily course schedules to Line, UniFlow makes it possible. Built with React Flow and Node.js, it offers a user-friendly canvas where logic is defined visually, bridging the gap between scattered campus information and students' digital lives.

UniFlow 是一個專為大學生打造的輕量級視覺化自動化平台。透過直觀的節點拖拉介面，使用者能輕鬆串接 Line、Discord 與 Google Sheets 等常用服務，無需編寫複雜程式碼，即可將校園資訊獲取與日常任務處理實現完全自動化。

UniFlow 的設計靈感源自 n8n 等工業級 iPaaS 解決方案，並將其簡化以適應學術與校園場景。無論是當 Google 表單有人報名時自動發送 Discord 通知，或是每天定時抓取課表推送到 Line，UniFlow 都能輕鬆達成。本平台基於 React Flow 與 Node.js 構建，提供了一個友善的視覺化畫布，讓邏輯定義變得直觀可見，成功橋接了零散的校園資訊與學生的數位生活。

## Features

*   **Visual Workflow Canvas**: Drag, drop, and connect nodes to build your automations.
*   **Dynamic Node Management**: Easily add and delete nodes on the canvas.
*   **Node Customization**: Personalize nodes by changing their names and background colors.
*   **Interactive UI**: Collapse and expand nodes to keep your workspace organized.
*   **State Persistence**: Save your entire workflow to the browser's local storage and restore it anytime.
*   **Intuitive Interface**: Powered by React Flow for a smooth and responsive user experience.

## Getting Started

### Prerequisites

*   Node.js (v18 or higher recommended)
*   npm

### Installation

1.  Clone the repository:
    ```bash
    git clone https://github.com/your-username/uniflow.git
    cd uniflow
    ```

2.  Install dependencies for both the frontend and backend:
    ```bash
    # Install frontend dependencies
    cd frontend
    npm install

    # Install backend dependencies
    cd ../backend
    npm install
    ```

## Usage

To run the application, you will need to start both the frontend and backend servers in separate terminals.

### Frontend

Navigate to the `frontend` directory and start the development server:

```bash
cd frontend
npm start
```

The frontend will be available at `http://localhost:5173`.

### Backend

Navigate to the `backend` directory and start the server:

```bash
cd backend
node index.js
```

The backend server will run at `http://localhost:3000`.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
