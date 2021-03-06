#' A function to generate a document term matrix from a list of document term vectors.
#'
#' @param document_term_vector_list A list of term vectors, one per document, that we wish to turn into a document term matrix.
#' @param vocabulary An optional vocabulary vector which will be used to form the document term matrix. Defaults to NULL, in which case a vocabulary vector will be generated internally.
#' @param document_term_count_list A list of vectors of word counts can optionally be provided, in which case we will aggregate over them. This can be useful if we wish to store documents in a memory efficent way. Defaults to NULL.
#' @param return_sparse_matrix Defualts to FALSE, in whih case a normal dense matrix is returned. If TRUE, then a sparse matrix object generated by the slam library is returned. A sparse matrix representation is also used in the C++ code if this is set to TRUE, which can result in drastic memory savings.
#' @return A dense document term matrix object with the vocabulary as column names.
#' @export
generate_document_term_matrix <- function(document_term_vector_list,
                                          vocabulary = NULL,
                                          document_term_count_list = NULL,
                                          return_sparse_matrix = FALSE){

    if(is.null(document_term_count_list) & return_sparse_matrix){
        cat("No document_term_count_list was provided, generating one...\n")
        # allocate the list
        document_term_count_list <- vector(mode = "list",
            length = length(document_term_vector_list))

        num_of_each_term <- function(index,vec,uni_terms){
            return(length(which(vec == uni_terms[index])))
        }

        if (length(document_term_vector_list) < 51) {
            printseq <- 1:length(document_term_vector_list)
        } else {
            printseq <- round(seq(1,length(document_term_vector_list),
                                  length.out = 51)[2:51],0)
        }
        print_counter <- 1
        #reformat the lists so they work with sparse matrices
        for (j in 1:length(document_term_vector_list)) {
            if(j == printseq[print_counter]) {
                cat(".")
                print_counter <- print_counter + 1
            }
            cur <- document_term_vector_list[[j]]
            uni_cur <- unique(cur)
            indices <- 1:length(uni_cur)
            counts <- sapply(X = indices,
                             FUN = num_of_each_term,
                             vec = cur,
                             uni_terms = uni_cur)
            document_term_count_list[[j]] <- counts
            document_term_vector_list[[j]] <- uni_cur
        }
        cat("\n")
        cat("Completed generating document_term_count_list...\n")
    }

    USING_STEM_LOOKUP_VOCABULARY = FALSE
    if(class(vocabulary) == "list"){
        if(vocabulary$type == "standard"){
            vocabulary = vocabulary$vocabulary
        }else if(vocabulary$type == "stem-lookup"){
            USING_STEM_LOOKUP_VOCABULARY = TRUE
        }else{
            stop("You have provided a vocabulary in a list form. If you are providing your own vocabulary you must provide it as a character vector.")
        }
    }

    #if a vocabulary was not supplied, then we generate it.
    if(is.null(vocabulary)){
        vocab <- count_words(document_term_vector_list,
                             maximum_vocabulary_size = -1,
                             document_term_count_list = document_term_count_list)
        vocabulary <- vocab$unique_words
    }

    number_of_documents <- length(document_term_vector_list)
    if(USING_STEM_LOOKUP_VOCABULARY){
        number_of_unique_words <- length(vocabulary$vocabulary)
    }else{
        number_of_unique_words <- length(vocabulary)
    }

    document_lengths <- unlist(lapply(document_term_vector_list, length))

    using_wordcounts <- 0
    # if we are providing word counts
    if(!is.null(document_term_count_list)){
        using_wordcounts <- 1
        if(typeof(document_term_count_list) == "numeric"){
            document_term_count_list <- as.integer(document_term_count_list)
            document_term_count_list <- list(document_term_count_list)
        }else if(typeof(document_term_count_list) == "integer"){
            document_term_count_list <- list(document_term_count_list)
        }else if(typeof(document_term_count_list) != "list"){
            stop("document_term_count_list must be a list object containing integer vectors or a single integer or numeric vector.")
        }
        if(length(document_term_count_list) != length(document_term_vector_list)){
            stop("document_term_vector_list and document_word_list must be the same length.")
        }
    }else{
        document_term_count_list <- as.list(rep(0,number_of_documents))
    }

    if(return_sparse_matrix){
        if(USING_STEM_LOOKUP_VOCABULARY){
            # fastest implementation for large vocabularies

            total_terms <- sum(unlist(lapply(document_term_vector_list, length)))
            sparse_list <- Generate_Sparse_Document_Term_Matrix_Stem_Vocabulary(
                number_of_documents,
                number_of_unique_words,
                unique_words = vocabulary$vocabulary,
                document_term_vector_list,
                document_lengths,
                document_term_count_list,
                total_terms,
                stem_lookup = vocabulary$stems,
                starts = (vocabulary$stem_first_use -1),
                ends = vocabulary$stem_last_use,
                lookup_size = length(vocabulary$stems))
            #cat(str(sparse_list),"\n")
            cat("Completed Generating Sparse Doc-Term Matrix...\n")

            document_term_matrix <- slam::simple_triplet_matrix(
                i = sparse_list[[1]],
                j = sparse_list[[2]],
                v = sparse_list[[3]],
                nrow = number_of_documents,
                ncol = number_of_unique_words
            )
            document_term_matrix$dimnames[[2]] <- vocabulary$vocabulary
            #cat(str(document_term_matrix),"\n")

        }else{
            #generate a placeholder object insert results into
            total_terms <- sum(unlist(lapply(document_term_vector_list, length)))
            sparse_list <- Generate_Sparse_Document_Term_Matrix(
                number_of_documents,
                number_of_unique_words,
                vocabulary,
                document_term_vector_list,
                document_lengths,
                document_term_count_list,
                total_terms)

            document_term_matrix <- slam::simple_triplet_matrix(
                i = sparse_list[[1]],
                j = sparse_list[[2]],
                v = sparse_list[[3]],
                nrow = number_of_documents,
                ncol = number_of_unique_words
            )
            document_term_matrix$dimnames[[2]] <- vocabulary
        }
    }else{
        #if we just want to generate a vanilla dense document term matrix.
        document_term_matrix <- Generate_Document_Term_Matrix(
            number_of_documents,
            number_of_unique_words,
            vocabulary,
            document_term_vector_list,
            document_lengths,
            using_wordcounts,
            document_term_count_list)

        colnames(document_term_matrix) <- vocabulary
    }

    return(document_term_matrix)
}
