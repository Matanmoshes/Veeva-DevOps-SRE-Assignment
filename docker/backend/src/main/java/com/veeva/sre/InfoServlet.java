package com.veeva.sre;

import java.io.IOException;
import java.io.PrintWriter;
import java.util.Date;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@WebServlet(name = "InfoServlet", urlPatterns = {"/info"})
public class InfoServlet extends HttpServlet {
    
    private static final long serialVersionUID = 1L;
    
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        
        PrintWriter out = response.getWriter();
        
        // Create info response
        StringBuilder json = new StringBuilder();
        json.append("{\n");
        json.append("  \"application\": \"Veeva SRE Backend\",\n");
        json.append("  \"version\": \"1.0.0\",\n");
        json.append("  \"build_time\": \"").append(new Date().toString()).append("\",\n");
        json.append("  \"java_version\": \"").append(System.getProperty("java.version")).append("\",\n");
        json.append("  \"server_info\": \"").append(getServletContext().getServerInfo()).append("\",\n");
        json.append("  \"environment\": \"").append(System.getenv("ENVIRONMENT") != null ? System.getenv("ENVIRONMENT") : "dev").append("\",\n");
        json.append("  \"memory\": {\n");
        json.append("    \"total\": ").append(Runtime.getRuntime().totalMemory()).append(",\n");
        json.append("    \"free\": ").append(Runtime.getRuntime().freeMemory()).append(",\n");
        json.append("    \"max\": ").append(Runtime.getRuntime().maxMemory()).append("\n");
        json.append("  },\n");
        json.append("  \"endpoints\": [\n");
        json.append("    \"/health\",\n");
        json.append("    \"/info\",\n");
        json.append("    \"/metrics\"\n");
        json.append("  ]\n");
        json.append("}\n");
        
        out.print(json.toString());
        response.setStatus(HttpServletResponse.SC_OK);
    }
} 