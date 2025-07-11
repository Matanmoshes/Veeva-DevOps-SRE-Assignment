// API Base URL - will be set dynamically
const API_BASE_URL = '/api';

// DOM Content Loaded Event
document.addEventListener('DOMContentLoaded', function() {
    initializeApp();
    checkSystemStatus();
    setInterval(checkSystemStatus, 30000); // Check every 30 seconds
});

// Initialize the application
function initializeApp() {
    console.log('Veeva SRE Application Initialized');
    updateTimestamp();
    setInterval(updateTimestamp, 1000); // Update timestamp every second
}

// Check system status
async function checkSystemStatus() {
    // Check frontend status
    updateStatusIndicator('frontend-status', 'Active', 'active');
    
    // Check backend status
    try {
        const response = await fetch(`${API_BASE_URL}/health`);
        if (response.ok) {
            updateStatusIndicator('backend-status', 'Active', 'active');
        } else {
            updateStatusIndicator('backend-status', 'Error', 'error');
        }
    } catch (error) {
        updateStatusIndicator('backend-status', 'Connecting...', 'loading');
    }
}

// Update status indicator
function updateStatusIndicator(elementId, text, className) {
    const element = document.getElementById(elementId);
    if (element) {
        element.textContent = text;
        element.className = `status-indicator ${className}`;
    }
}

// Update timestamp
function updateTimestamp() {
    const now = new Date();
    const timestamp = now.toLocaleString();
    // You can add a timestamp display element if needed
}

// Test backend health endpoint
async function testBackendHealth() {
    const output = document.getElementById('api-output');
    output.textContent = 'Testing health endpoint...';
    
    try {
        const response = await fetch(`${API_BASE_URL}/health`);
        const data = await response.text();
        
        output.textContent = `Status: ${response.status} ${response.statusText}\n\nResponse:\n${data}`;
        output.className = response.ok ? 'success' : 'error';
    } catch (error) {
        output.textContent = `Error: ${error.message}`;
        output.className = 'error';
    }
}

// Test backend info endpoint
async function testBackendInfo() {
    const output = document.getElementById('api-output');
    output.textContent = 'Testing info endpoint...';
    
    try {
        const response = await fetch(`${API_BASE_URL}/info`);
        
        if (response.headers.get('content-type')?.includes('application/json')) {
            const data = await response.json();
            output.textContent = `Status: ${response.status} ${response.statusText}\n\nResponse:\n${JSON.stringify(data, null, 2)}`;
        } else {
            const data = await response.text();
            output.textContent = `Status: ${response.status} ${response.statusText}\n\nResponse:\n${data}`;
        }
        
        output.className = response.ok ? 'success' : 'error';
    } catch (error) {
        output.textContent = `Error: ${error.message}`;
        output.className = 'error';
    }
}

// Test backend metrics endpoint
async function testBackendMetrics() {
    const output = document.getElementById('api-output');
    output.textContent = 'Testing metrics endpoint...';
    
    try {
        const response = await fetch(`${API_BASE_URL}/metrics`);
        
        if (response.headers.get('content-type')?.includes('application/json')) {
            const data = await response.json();
            output.textContent = `Status: ${response.status} ${response.statusText}\n\nResponse:\n${JSON.stringify(data, null, 2)}`;
        } else {
            const data = await response.text();
            output.textContent = `Status: ${response.status} ${response.statusText}\n\nResponse:\n${data}`;
        }
        
        output.className = response.ok ? 'success' : 'error';
    } catch (error) {
        output.textContent = `Error: ${error.message}`;
        output.className = 'error';
    }
}

// Utility function to format JSON
function formatJSON(obj) {
    return JSON.stringify(obj, null, 2);
}

// Utility function to handle API errors
function handleApiError(error, output) {
    console.error('API Error:', error);
    output.textContent = `Error: ${error.message}`;
    output.className = 'error';
}

// Smooth scrolling for navigation links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    });
});

// Add some animation to cards
function animateCards() {
    const cards = document.querySelectorAll('.card, .dashboard-card');
    cards.forEach((card, index) => {
        card.style.animationDelay = `${index * 0.1}s`;
        card.classList.add('animate-in');
    });
}

// Call animation on load
document.addEventListener('DOMContentLoaded', animateCards);

// Add CSS animation styles dynamically
const style = document.createElement('style');
style.textContent = `
    @keyframes slideInUp {
        from {
            opacity: 0;
            transform: translateY(30px);
        }
        to {
            opacity: 1;
            transform: translateY(0);
        }
    }
    
    .animate-in {
        animation: slideInUp 0.6s ease-out forwards;
    }
`;
document.head.appendChild(style); 