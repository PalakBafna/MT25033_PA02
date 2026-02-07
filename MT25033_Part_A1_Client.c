/*
 * MT25033_Part_A1_Client.c
 * Two-Copy Client Implementation using recv()
 * Roll Number: MT25033
 *
 * This is the baseline implementation using standard recv() socket primitive.
 *
 * TWO-COPY EXPLANATION (Receive side):
 * Copy 1: NIC DMA buffer -> Kernel socket buffer (by network driver)
 * Copy 2: Kernel socket buffer -> User space buffer (during recv() syscall)
 *
 * The client:
 * - Spawns multiple threads to connect to server
 * - Each thread receives data continuously for a fixed duration
 * - Measures throughput and latency
 */

#include "MT25033_Part_A_Common.h"
#include <signal.h>
#include <getopt.h>

/* Global flag for graceful shutdown */
static volatile int running = 1;

/* Global metrics protected by mutex */
static pthread_mutex_t metrics_mutex = PTHREAD_MUTEX_INITIALIZER;
static Metrics global_metrics = {0};

/* Signal handler for graceful termination */
void signal_handler(int signum) {
    (void)signum;
    running = 0;
}

/*
 * Thread function for client connection
 * Connects to server and receives messages continuously
 */
void* client_thread(void *arg) {
    ClientThreadArgs *args = (ClientThreadArgs*)arg;
    size_t msg_size = args->msg_size;

    /* Create socket */
    int sock_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (sock_fd < 0) {
        perror("socket creation failed");
        pthread_exit(NULL);
    }

    /* Set up server address */
    struct sockaddr_in server_addr;
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(args->server_port);

    if (inet_pton(AF_INET, args->server_ip, &server_addr.sin_addr) <= 0) {
        perror("Invalid address");
        close(sock_fd);
        pthread_exit(NULL);
    }

    /* Connect to server */
    if (connect(sock_fd, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        perror("connect failed");
        close(sock_fd);
        pthread_exit(NULL);
    }

    printf("[Thread %d] Connected to server %s:%d\n",
           args->thread_id, args->server_ip, args->server_port);

    /* Allocate receive buffer */
    char *recv_buffer = (char*)malloc(msg_size);
    if (!recv_buffer) {
        perror("Failed to allocate receive buffer");
        close(sock_fd);
        pthread_exit(NULL);
    }

    args->bytes_received = 0;
    args->messages_received = 0;
    args->total_latency = 0;

    double start_time = get_time_sec();
    double end_time = start_time + args->duration;

    /* Receive messages continuously until duration expires */
    while (running && get_time_sec() < end_time) {
        double msg_start = get_time_us();

        /*
         * TWO-COPY recv():
         * This call copies data from kernel socket buffer to user space buffer
         * The kernel previously copied from NIC to socket buffer
         */
        ssize_t received = recv(sock_fd, recv_buffer, msg_size, 0);

        double msg_end = get_time_us();

        if (received < 0) {
            if (errno == EINTR) continue;
            perror("recv failed");
            break;
        }

        if (received == 0) {
            printf("[Thread %d] Server closed connection\n", args->thread_id);
            break;
        }

        args->bytes_received += received;
        args->messages_received++;
        args->total_latency += (msg_end - msg_start);
    }

    args->elapsed_time = get_time_sec() - start_time;

    /* Calculate thread metrics */
    double throughput = calc_throughput_gbps(args->bytes_received, args->elapsed_time);
    double avg_latency = args->messages_received > 0 ?
                         args->total_latency / args->messages_received : 0;

    printf("[Thread %d] Finished: received %lu bytes (%lu messages) in %.2f seconds\n",
           args->thread_id, args->bytes_received, args->messages_received, args->elapsed_time);
    printf("[Thread %d] Throughput: %.4f Gbps, Avg Latency: %.2f µs\n",
           args->thread_id, throughput, avg_latency);

    /* Update global metrics */
    pthread_mutex_lock(&metrics_mutex);
    global_metrics.total_bytes += args->bytes_received;
    global_metrics.total_messages += args->messages_received;
    global_metrics.total_time = args->elapsed_time; /* Use last thread's time */
    global_metrics.avg_latency_us += avg_latency;
    pthread_mutex_unlock(&metrics_mutex);

    /* Cleanup */
    free(recv_buffer);
    close(sock_fd);

    return NULL;
}

int main(int argc, char *argv[]) {
    const char *server_ip = "127.0.0.1";
    int server_port = DEFAULT_PORT;
    size_t msg_size = DEFAULT_MSG_SIZE;
    int num_threads = DEFAULT_NUM_THREADS;
    int duration = DEFAULT_DURATION;
    int opt;

    /* Parse command line arguments */
    while ((opt = getopt(argc, argv, "i:p:s:t:d:h")) != -1) {
        switch (opt) {
            case 'i':
                server_ip = optarg;
                break;
            case 'p':
                server_port = atoi(optarg);
                break;
            case 's':
                msg_size = atoi(optarg);
                break;
            case 't':
                num_threads = atoi(optarg);
                break;
            case 'd':
                duration = atoi(optarg);
                break;
            case 'h':
            default:
                print_usage(argv[0], 0);
                exit(EXIT_SUCCESS);
        }
    }

    /* Set up signal handler */
    signal(SIGINT, signal_handler);

    printf("=== Two-Copy Client (send/recv) ===\n");
    printf("Connecting to %s:%d\n", server_ip, server_port);
    printf("Message size: %zu bytes, Threads: %d, Duration: %d seconds\n",
           msg_size, num_threads, duration);
    printf("\n");

    /* Allocate thread resources */
    pthread_t *threads = (pthread_t*)malloc(num_threads * sizeof(pthread_t));
    ClientThreadArgs *thread_args = (ClientThreadArgs*)malloc(num_threads * sizeof(ClientThreadArgs));

    if (!threads || !thread_args) {
        perror("Failed to allocate thread resources");
        exit(EXIT_FAILURE);
    }

    /* Create client threads */
    for (int i = 0; i < num_threads; i++) {
        thread_args[i].thread_id = i;
        thread_args[i].server_ip = server_ip;
        thread_args[i].server_port = server_port;
        thread_args[i].msg_size = msg_size;
        thread_args[i].duration = duration;

        if (pthread_create(&threads[i], NULL, client_thread, &thread_args[i]) != 0) {
            perror("pthread_create failed");
            num_threads = i;
            break;
        }
    }

    /* Wait for all threads to complete */
    for (int i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
    }

    /* Calculate final metrics */
    global_metrics.throughput_gbps = calc_throughput_gbps(global_metrics.total_bytes,
                                                          global_metrics.total_time);
    global_metrics.avg_latency_us /= num_threads;

    printf("\n=== Final Statistics ===\n");
    printf("Total bytes received: %lu\n", global_metrics.total_bytes);
    printf("Total messages received: %lu\n", global_metrics.total_messages);
    printf("Aggregate throughput: %.4f Gbps\n", global_metrics.throughput_gbps);
    printf("Average latency: %.2f µs\n", global_metrics.avg_latency_us);

    /* Output CSV-friendly line for scripting */
    printf("\nCSV: two_copy,%zu,%d,%.4f,%.2f,%lu\n",
           msg_size, num_threads, global_metrics.throughput_gbps,
           global_metrics.avg_latency_us, global_metrics.total_bytes);

    /* Cleanup */
    free(threads);
    free(thread_args);

    return 0;
}
