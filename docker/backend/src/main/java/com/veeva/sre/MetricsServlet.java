package com.veeva.sre;

import java.io.IOException;
import java.io.PrintWriter;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.OperatingSystemMXBean;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@WebServlet(name = "MetricsServlet", urlPatterns = {"/metrics"})
public class MetricsServlet extends HttpServlet {
    
    private static final long serialVersionUID = 1L;
    
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        
        response.setContentType("text/plain");
        response.setCharacterEncoding("UTF-8");
        
        PrintWriter out = response.getWriter();
        
        // Get system metrics
        MemoryMXBean memoryBean = ManagementFactory.getMemoryMXBean();
        OperatingSystemMXBean osBean = ManagementFactory.getOperatingSystemMXBean();
        Runtime runtime = Runtime.getRuntime();
        
        // Create metrics response in Prometheus format
        long timestamp = System.currentTimeMillis();
        long uptime = ManagementFactory.getRuntimeMXBean().getUptime();
        
        // JVM metrics
        out.println("# HELP jvm_memory_heap_used_bytes Used heap memory in bytes");
        out.println("# TYPE jvm_memory_heap_used_bytes gauge");
        out.println("jvm_memory_heap_used_bytes " + memoryBean.getHeapMemoryUsage().getUsed());
        
        out.println("# HELP jvm_memory_heap_max_bytes Maximum heap memory in bytes");
        out.println("# TYPE jvm_memory_heap_max_bytes gauge");
        out.println("jvm_memory_heap_max_bytes " + memoryBean.getHeapMemoryUsage().getMax());
        
        out.println("# HELP jvm_memory_heap_committed_bytes Committed heap memory in bytes");
        out.println("# TYPE jvm_memory_heap_committed_bytes gauge");
        out.println("jvm_memory_heap_committed_bytes " + memoryBean.getHeapMemoryUsage().getCommitted());
        
        out.println("# HELP jvm_memory_non_heap_used_bytes Used non-heap memory in bytes");
        out.println("# TYPE jvm_memory_non_heap_used_bytes gauge");
        out.println("jvm_memory_non_heap_used_bytes " + memoryBean.getNonHeapMemoryUsage().getUsed());
        
        // System metrics
        out.println("# HELP system_cpu_count Number of available processors");
        out.println("# TYPE system_cpu_count gauge");
        out.println("system_cpu_count " + osBean.getAvailableProcessors());
        
        out.println("# HELP system_load_average System load average");
        out.println("# TYPE system_load_average gauge");
        out.println("system_load_average " + osBean.getSystemLoadAverage());
        
        // JVM uptime
        out.println("# HELP jvm_uptime_seconds JVM uptime in seconds");
        out.println("# TYPE jvm_uptime_seconds counter");
        out.println("jvm_uptime_seconds " + (uptime / 1000.0));
        
        // GC metrics
        long gcCount = ManagementFactory.getGarbageCollectorMXBeans().stream()
                .mapToLong(gc -> gc.getCollectionCount()).sum();
        long gcTime = ManagementFactory.getGarbageCollectorMXBeans().stream()
                .mapToLong(gc -> gc.getCollectionTime()).sum();
        
        out.println("# HELP jvm_gc_collection_total Total GC collections");
        out.println("# TYPE jvm_gc_collection_total counter");
        out.println("jvm_gc_collection_total " + gcCount);
        
        out.println("# HELP jvm_gc_collection_time_seconds Total GC collection time in seconds");
        out.println("# TYPE jvm_gc_collection_time_seconds counter");
        out.println("jvm_gc_collection_time_seconds " + (gcTime / 1000.0));
        
        response.setStatus(HttpServletResponse.SC_OK);
    }
} 