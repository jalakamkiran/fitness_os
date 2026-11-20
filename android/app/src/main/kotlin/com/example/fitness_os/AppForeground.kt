package com.example.fitness_os

object AppForeground {
    @Volatile
    var isResumed: Boolean = false
}