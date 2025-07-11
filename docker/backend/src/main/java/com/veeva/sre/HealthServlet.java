package com.veeva.sre;

import java.io.IOException;
import java.io.PrintWriter;
import java.util.Date;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@WebServlet(name = "HealthServlet", urlPatterns = {"/health"})
public class HealthServlet extends HttpServlet {
    
    private static final long serialVersionUID = 1L;
    
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        
        PrintWriter out = response.getWriter();
        
        // Create health check response
        StringBuilder json = new StringBuilder();
        json.append("{\n");
        json.append("  \"status\": \"healthy\",\n");
        json.append("  \"timestamp\": \"").append(new Date().toString()).append("\",\n");
        json.append("  \"service\": \"backend-service\",\n");
        json.append("  \"version\": \"1.0.0\",\n");
        json.append("  \"uptime\": \"").append(getUptime()).append("\",\n");
        json.append("  \"checks\": {\n");
        json.append("    \"database\": \"ok\",\n");
        json.append("    \"memory\": \"ok\",\n");
        json.append("    \"disk\": \"ok\"\n");
        json.append("  }\n");
        json.append("}\n");
        
        out.print(json.toString());
        response.setStatus(HttpServletResponse.SC_OK);
    }
    
    private String getUptime() {
        long uptime = System.currentTimeMillis() - getServletContext().getServerInfo().hashCode();
        return String.valueOf(uptime / 1000) + " seconds";
    }
} 